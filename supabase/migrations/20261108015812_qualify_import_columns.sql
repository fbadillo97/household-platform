create or replace function household_private.v1(operation text, payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' set datestyle='ISO, YMD' as $$
declare
 actor uuid := household_private.identity_id(); actor_role text; m household_private.memberships;
 cfg household_private.settings; target uuid; ident uuid; b household_private.import_batches;
 result jsonb; item jsonb; row_data record; parsed_day date; description text; cents bigint;
 error_message text; fp text; amount numeric; row_number integer:=1; ids uuid[]; allowed_duplicates uuid[];
 limit_count integer; offset_count integer;
begin
 if payload is null or jsonb_typeof(payload)<>'object' then
  raise exception using errcode='22023',message='Object payload required'; end if;
 if operation in ('access_state','request_access') then
  if operation='request_access' then
   select * into cfg from household_private.settings where singleton for update;
   if cfg.owner_user_id is null and cfg.owner_email is not null and exists(
    select 1 from auth.users where id=actor and lower(email)=cfg.owner_email
   ) then
    insert into household_private.memberships(user_id,status,role) values(actor,'approved','owner')
     on conflict(user_id) do update set status='approved',role='owner',revision=household_private.memberships.revision+1,updated_at=now();
    update household_private.settings set owner_user_id=actor where singleton;
    insert into household_private.audit_events(actor_id,action,target_id) values(actor,'owner_bootstrapped',actor);
   else
    insert into household_private.memberships(user_id) values(actor) on conflict do nothing;
   end if;
  end if;
  select * into m from household_private.memberships where user_id=actor;
  return jsonb_build_object('status',coalesce(m.status,'unrequested'),'role',m.role,'revision',m.revision);
 end if;
 actor_role := household_private.member_role();
 if operation='list_requests' then
  if actor_role<>'owner' then raise exception using errcode='42501',message='Owner access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('user_id',q.user_id,'email',u.email,'status',q.status,'role',q.role,
   'revision',q.revision,'created_at',q.created_at) order by q.created_at),'[]'::jsonb) into result
   from household_private.memberships q join auth.users u on u.id=q.user_id;
  return result;
 elsif operation='decide_access' then
  if actor_role<>'owner' then raise exception using errcode='42501',message='Owner access required'; end if;
  target := (payload->>'user_id')::uuid;
  select * into m from household_private.memberships where user_id=target for update;
  if m.user_id is null then raise exception using errcode='P0002',message='Request not found'; end if;
  if m.role='owner' or m.user_id=actor then raise exception using errcode='42501',message='Owner access cannot be changed here'; end if;
  if (payload->>'status') is null or (payload->>'status') not in ('approved','rejected','removed') then
   raise exception using errcode='22023',message='Invalid decision'; end if;
  if (payload->>'revision')::integer is distinct from m.revision then
   raise exception using errcode='40001',message='Request changed; refresh before deciding'; end if;
  update household_private.memberships set status=payload->>'status',revision=revision+1,updated_at=now() where user_id=target;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,'access_'||(payload->>'status'),target);
  return jsonb_build_object('status',payload->>'status');
 elsif operation='list_accounts' then
  select coalesce(jsonb_agg(to_jsonb(a) order by a.name),'[]'::jsonb) into result from household_private.accounts a; return result;
 elsif operation='list_properties' then
  select coalesce(jsonb_agg(to_jsonb(p) order by p.name),'[]'::jsonb) into result from household_private.properties p; return result;
 elsif operation='list_categories' then
  select coalesce(jsonb_agg(to_jsonb(c) order by c.name),'[]'::jsonb) into result from household_private.categories c; return result;
 elsif operation in ('create_account','create_property','create_category') then
  if length(btrim(coalesce(payload->>'name',''))) not between 1 and 120 then
   raise exception using errcode='22023',message='Name must contain 1–120 characters'; end if;
  if operation='create_account' then
   insert into household_private.accounts(name,kind,currency) values(btrim(payload->>'name'),payload->>'kind',coalesce(payload->>'currency','CAD')) returning to_jsonb(accounts.*),id into result,ident;
  elsif operation='create_property' then
   insert into household_private.properties(name,kind) values(btrim(payload->>'name'),payload->>'kind') returning to_jsonb(properties.*),id into result,ident;
  else
   insert into household_private.categories(name) values(btrim(payload->>'name')) returning to_jsonb(categories.*),id into result,ident;
  end if;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident); return result;
 elsif operation='list_transactions' then
  limit_count:=coalesce((payload->>'limit')::integer,100); offset_count:=coalesce((payload->>'offset')::integer,0);
  if limit_count not between 1 and 500 or offset_count<0 then raise exception using errcode='22023',message='Invalid pagination'; end if;
  select coalesce(jsonb_agg(to_jsonb(t) order by t.date desc,t.id),'[]'::jsonb) into result from (
   select * from household_private.transactions
   where (payload->>'account_id' is null or account_id=(payload->>'account_id')::uuid)
    and (payload->>'property_id' is null or property_id=(payload->>'property_id')::uuid)
   order by date desc,id limit limit_count offset offset_count
  ) t; return result;
 elsif operation='assign_transaction' then
  update household_private.transactions set property_id=(payload->>'property_id')::uuid,category_id=(payload->>'category_id')::uuid,revision=revision+1
   where id=(payload->>'id')::uuid and revision=(payload->>'revision')::integer returning to_jsonb(transactions.*) into result;
  if result is null then raise exception using errcode='40001',message='Transaction changed or not found; refresh'; end if;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,(payload->>'id')::uuid); return result;
 elsif operation='stage_import' then
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows') not between 1 and 5000
   or octet_length(payload::text)>2000000 then raise exception using errcode='22023',message='Import requires 1–5000 rows, maximum 2 MB'; end if;
  insert into household_private.import_batches(account_id,created_by) values((payload->>'account_id')::uuid,actor) returning id into ident;
  for item in select value from jsonb_array_elements(payload->'rows') loop
   row_number:=row_number+1; error_message:=null; parsed_day:=null; description:=null; cents:=null; fp:=null;
   begin
    if jsonb_typeof(item)<>'object' or item->>'parse_error' is not null then raise exception 'Invalid CSV columns'; end if;
    if coalesce(item->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Use YYYY-MM-DD dates'; end if;
    parsed_day:=(item->>'date')::date;
    if parsed_day::text <> item->>'date' then raise exception 'Invalid date'; end if;
    description:=btrim(item->>'description');
    if description is null or length(description) not between 1 and 500 then raise exception 'Description must contain 1–500 characters'; end if;
    if coalesce(item->>'amount','') !~ '^[+-]?[0-9]{1,10}(\.[0-9]{1,2})?$' then raise exception 'Use a decimal amount with at most two places'; end if;
    amount:=(item->>'amount')::numeric;
    if abs(amount)>1000000000 then raise exception 'Amount exceeds limit'; end if;
    cents:=(amount*100)::bigint;
    fp:=encode(sha256(convert_to(jsonb_build_array(parsed_day,lower(regexp_replace(btrim(description),'\s+',' ','g')),cents)::text,'UTF8')),'hex');
   exception when others then error_message:='Invalid row: check date, description, amount and column count'; parsed_day:=null;description:=null;cents:=null;fp:=null;
   end;
   insert into household_private.staged_rows(batch_id,line,date,description,amount_minor,fingerprint,error)
    values(ident,row_number,parsed_day,description,cents,fp,error_message);
  end loop;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);
  return household_private.preview_import(ident,actor);
 elsif operation='preview_import' then return household_private.preview_import((payload->>'id')::uuid,actor);
 elsif operation='commit_import' then
  select * into b from household_private.import_batches where id=(payload->>'id')::uuid and created_by=actor for update;
  if b.id is null then raise exception using errcode='P0002',message='Import not found'; end if;
  if b.committed_at is not null then raise exception using errcode='40001',message='Import already committed'; end if;
  -- Serialize imports per account, then re-evaluate duplicates against the latest committed records.
  perform 1 from household_private.accounts where id=b.account_id for update;
  if jsonb_typeof(payload->'row_ids') is distinct from 'array' or jsonb_array_length(payload->'row_ids') not between 1 and 5000 then
   raise exception using errcode='22023',message='Select 1–5000 valid row IDs'; end if;
  select array_agg(value::uuid) into ids from jsonb_array_elements_text(payload->'row_ids');
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into allowed_duplicates from jsonb_array_elements_text(coalesce(payload->'duplicate_ids','[]'::jsonb));
  if cardinality(ids)<>(select count(distinct x) from unnest(ids) x) or not allowed_duplicates <@ ids then
   raise exception using errcode='22023',message='Invalid or repeated selection'; end if;
  if cardinality(ids)<>(select count(*) from household_private.staged_rows where batch_id=b.id and id=any(ids) and error is null) then
   raise exception using errcode='22023',message='Selection contains invalid rows'; end if;
  result:=household_private.preview_import(b.id,actor);
  if exists(select 1 from jsonb_array_elements(result->'rows') s where (s->>'id')::uuid=any(ids) and (s->>'duplicate')::boolean and not (s->>'id')::uuid=any(allowed_duplicates)) then
   raise exception using errcode='40001',message='Duplicate review required; refresh the preview'; end if;
  insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,batch_id)
   select b.account_id,s.date,s.description,s.amount_minor,s.fingerprint,b.id from household_private.staged_rows s where s.batch_id=b.id and s.id=any(ids);
  update household_private.import_batches set committed_at=now(),selected_count=cardinality(ids) where id=b.id;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,b.id);
  return jsonb_build_object('inserted',cardinality(ids));
 else raise exception using errcode='22023',message='Unknown operation';
 end if;
end $$;

