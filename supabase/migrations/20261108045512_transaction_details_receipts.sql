alter table household_private.transactions add column notes text not null default '' check(length(notes)<=10000);
alter table household_private.transactions add column review_status text not null default 'unreviewed' check(review_status in ('unreviewed','reviewed'));
alter table household_private.transactions add column needs_attention boolean not null default false;
alter table household_private.transactions add column reviewed_at timestamptz;
alter table household_private.transactions add column reviewed_by uuid references auth.users(id);
alter table household_private.transactions add column tags_override text[];
alter table household_private.transactions add column deleted_at timestamptz;
alter table household_private.transactions add column deleted_by uuid references auth.users(id);
create index transactions_reviewed_by_idx on household_private.transactions(reviewed_by);
create index transactions_deleted_by_idx on household_private.transactions(deleted_by);
create index transactions_deleted_at_idx on household_private.transactions(deleted_at);
create table household_private.receipts(
 id uuid primary key default gen_random_uuid(),transaction_id uuid not null references household_private.transactions(id),
 object_path text not null unique,filename text not null check(length(filename) between 1 and 180),
 mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
 byte_size bigint not null check(byte_size between 1 and 10485760),sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
 state text not null default 'pending' check(state in ('pending','ready','removed')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 removed_at timestamptz,revision integer not null default 1
);
create unique index receipts_active_hash_idx on household_private.receipts(transaction_id,sha256) where removed_at is null;
create index receipts_created_by_idx on household_private.receipts(created_by);
alter table household_private.receipts enable row level security;
revoke all on household_private.receipts from public,anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('household-receipts','household-receipts',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']);

-- Storage policies can only authorize exact, prepared paths after checking current passkey membership.
create function household_private.receipt_permission(object_name text,action text) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid;receipt household_private.receipts;trashed boolean;
begin
 actor:=household_private.identity_id();perform household_private.member_role();
 select * into receipt from household_private.receipts where object_path=object_name and removed_at is null;
 select deleted_at is not null into trashed from household_private.transactions where id=receipt.transaction_id;
 if receipt.id is null then return false;end if;
 if action='read' then return receipt.state='ready' or (receipt.state='pending' and receipt.created_by=actor);end if;
 if action='upload' then return not trashed and receipt.state='pending' and receipt.created_by=actor;end if;
 if action='remove' then return not trashed and (receipt.state='ready' or (receipt.state='pending' and receipt.created_by=actor));end if;
 return false;
exception when insufficient_privilege then return false;
end $$;
revoke all on function household_private.receipt_permission(text,text) from public,anon,authenticated;
grant execute on function household_private.receipt_permission(text,text) to authenticated;
create policy household_receipts_read on storage.objects for select to authenticated
 using(bucket_id='household-receipts' and household_private.receipt_permission(name,'read'));
create policy household_receipts_upload on storage.objects for insert to authenticated
 with check(bucket_id='household-receipts' and household_private.receipt_permission(name,'upload'));
create policy household_receipts_remove on storage.objects for delete to authenticated
 using(bucket_id='household-receipts' and household_private.receipt_permission(name,'remove'));

create function household_private.transaction_detail(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();result jsonb;
begin
 select to_jsonb(t)||jsonb_build_object('description',coalesce(t.description_override,t.description),'account_id',coalesce(t.account_override_id,t.account_id),
  'original_description',t.description,'original_account_id',t.account_id,
  'original_tags',coalesce((select jsonb_agg(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end)
   from jsonb_array_elements(case when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) tag),'[]'::jsonb),
  'receipts',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from household_private.receipts r where r.transaction_id=t.id and r.removed_at is null),'[]'::jsonb)) into result
  from household_private.transactions t where t.id=(payload->>'id')::uuid;
 if result is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 return result;
end $$;

create function household_private.transaction_trash(payload jsonb,restore boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();t household_private.transactions;
begin
 select * into t from household_private.transactions where id=(payload->>'id')::uuid for update;
 if t.id is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 if t.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Transaction changed; reload before continuing';end if;
 if restore and t.deleted_at is null then raise exception using errcode='40001',message='Transaction is already active';end if;
 if not restore and t.deleted_at is not null then raise exception using errcode='40001',message='Transaction is already in Trash';end if;
 update household_private.transactions set deleted_at=case when restore then null else now() end,deleted_by=case when restore then null else actor end,revision=revision+1 where id=t.id;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,case when restore then 'restore_transaction' else 'trash_transaction' end,t.id);
 return household_private.transaction_detail(jsonb_build_object('id',t.id));
end $$;

create function household_private.receipt_action(operation text,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();r household_private.receipts;t household_private.transactions;ident uuid;metadata jsonb;
begin
 if operation='prepare_receipt' then
  select * into t from household_private.transactions where id=(payload->>'transaction_id')::uuid for update;
 else
  select transaction_id into ident from household_private.receipts where id=(payload->>'id')::uuid;
  select * into t from household_private.transactions where id=ident for update;
 end if;
 if t.id is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 if t.deleted_at is not null then raise exception using errcode='40001',message='Restore the transaction before changing receipts';end if;
 if operation='prepare_receipt' then
  if length(btrim(coalesce(payload->>'filename',''))) not between 1 and 180 or (payload->>'filename') ~ '[[:cntrl:]]'
   or strpos(payload->>'filename','/')>0 or strpos(payload->>'filename',chr(92))>0
   or coalesce(payload->>'mime_type','') not in ('image/jpeg','image/png','image/webp','application/pdf')
   or coalesce(payload->>'sha256','') !~ '^[0-9a-f]{64}$'
   or coalesce((payload->>'byte_size')::bigint,0) not between 1 and 10485760 then
   raise exception using errcode='22023',message='Use a PDF, JPEG, PNG or WebP receipt up to 10 MB';end if;
  select * into r from household_private.receipts where transaction_id=t.id and sha256=payload->>'sha256' and removed_at is null;
  if r.id is not null then
   if r.state='pending' and r.created_by<>actor then raise exception using errcode='40001',message='Another upload of this receipt is in progress';end if;
   return to_jsonb(r)||jsonb_build_object('already_exists',r.state='ready');
  end if;
  if (select count(*) from household_private.receipts where transaction_id=t.id and removed_at is null)>=20 then
   raise exception using errcode='22023',message='Maximum 20 receipts per transaction';end if;
  ident:=gen_random_uuid();
  insert into household_private.receipts(id,transaction_id,object_path,filename,mime_type,byte_size,sha256,created_by)
   values(ident,t.id,t.id::text||'/'||ident::text,btrim(payload->>'filename'),payload->>'mime_type',(payload->>'byte_size')::bigint,payload->>'sha256',actor) returning * into r;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,'prepare_receipt',t.id);
  return to_jsonb(r);
 end if;
 select * into r from household_private.receipts where id=(payload->>'id')::uuid for update;
 if r.id is null or r.removed_at is not null then raise exception using errcode='P0002',message='Receipt not found';end if;
 if r.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Receipt changed; reload before continuing';end if;
 if operation='finish_receipt_upload' then
  if r.state='ready' then return to_jsonb(r);end if;
  if r.created_by<>actor then raise exception using errcode='42501',message='Only the uploader can finish this upload';end if;
  select o.metadata into metadata from storage.objects o where o.bucket_id='household-receipts' and o.name=r.object_path;
  if metadata is null or coalesce((metadata->>'size')::bigint,-1)<>r.byte_size or metadata->>'mimetype' is distinct from r.mime_type then
   raise exception using errcode='22023',message='Uploaded receipt is missing or does not match its prepared type/size';end if;
  update household_private.receipts set state='ready',revision=revision+1 where id=r.id returning * into r;
 elsif operation='finish_receipt_removal' then
  if r.state='pending' and r.created_by<>actor then raise exception using errcode='42501',message='Only the uploader can cancel this upload';end if;
  if exists(select 1 from storage.objects where bucket_id='household-receipts' and name=r.object_path) then
   raise exception using errcode='40001',message='Remove the stored file before finishing receipt removal';end if;
  update household_private.receipts set state='removed',removed_at=now(),revision=revision+1 where id=r.id returning * into r;
 else raise exception using errcode='22023',message='Unknown receipt operation';end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,t.id);
 return to_jsonb(r);
end $$;
revoke all on function household_private.transaction_detail(jsonb),household_private.transaction_trash(jsonb,boolean),household_private.receipt_action(text,jsonb) from public,anon,authenticated;

create or replace function household_private.ledger_query(payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 _role text:=household_private.member_role();_limit integer:=coalesce((payload->>'limit')::integer,50);_offset integer:=coalesce((payload->>'offset')::integer,0);
 _sort text:=coalesce(payload->>'sort','date');_direction text:=coalesce(payload->>'direction','desc');_trash boolean:=coalesce((payload->>'trash_only')::boolean,false);_review text:=coalesce(payload->>'review','');
 _account uuid:=nullif(payload->>'account_id','')::uuid;_category uuid:=nullif(nullif(payload->>'category_id','__unassigned'),'')::uuid;
 _from date:=(payload->>'date_from')::date;_to date:=(payload->>'date_to')::date;
 _min bigint:=(payload->>'min_minor')::bigint;_max bigint:=(payload->>'max_minor')::bigint;result jsonb;
begin
 if _limit not between 1 and 500 or _offset not between 0 and 1000000 or _sort not in ('date','description','account','amount','category','tags') or _direction not in ('asc','desc') then
  raise exception using errcode='22023',message='Invalid sort or pagination';end if;
 if _review not in ('','unreviewed','reviewed','needs_attention') then raise exception using errcode='22023',message='Invalid review filter';end if;
 if (_from is not null and _to is not null and _from>_to) or (_min is not null and _max is not null and _min>_max)
  or coalesce(payload->>'month','') !~ '^([0-9]{4}-(0[1-9]|1[0-2]))?$'
  or length(coalesce(payload->>'query',''))>500 or length(coalesce(payload->>'description',''))>500 or length(coalesce(payload->>'tags',''))>200 then
  raise exception using errcode='22023',message='Check the date, amount or text filters';end if;
 with effective as (
  select t.id,t.date,t.amount_minor,t.category_id,t.notes,t.review_status,t.needs_attention,t.deleted_at,coalesce(t.account_override_id,t.account_id) as effective_account,
   coalesce(t.description_override,t.description) as effective_description,a.name as account_name,c.name as category_name,tag_names.terms as tags_text,
   to_jsonb(t)||jsonb_build_object('description',coalesce(t.description_override,t.description),'account_id',coalesce(t.account_override_id,t.account_id),
    'original_description',t.description,'original_account_id',t.account_id,'account_name',a.name,'category_name',c.name,'tags_text',tag_names.terms,
    'receipt_count',(select count(*) from household_private.receipts r where r.transaction_id=t.id and r.state='ready' and r.removed_at is null),'has_description_override',t.description_override is not null,'has_account_override',t.account_override_id is not null) as row_data
  from household_private.transactions t
  join household_private.accounts a on a.id=coalesce(t.account_override_id,t.account_id)
  left join household_private.categories c on c.id=t.category_id
  left join lateral(select coalesce(string_agg(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end,' '),'') as terms
   from jsonb_array_elements(case when t.tags_override is not null then to_jsonb(t.tags_override) when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) tag) tag_names on true
 ), filtered as (
  select * from effective e where ((_trash and e.deleted_at is not null) or (not _trash and e.deleted_at is null))
   and (_review='' or (_review='needs_attention' and e.needs_attention) or e.review_status=_review) and (_account is null or e.effective_account=_account)
   and (coalesce(payload->>'category_id','')<>'__unassigned' or e.category_id is null) and (_category is null or e.category_id=_category)
   and (_from is null or e.date>=_from) and (_to is null or e.date<=_to)
   and (coalesce(payload->>'month','')='' or to_char(e.date,'YYYY-MM')=payload->>'month')
   and (_min is null or e.amount_minor>=_min) and (_max is null or e.amount_minor<=_max)
   and strpos(lower(e.effective_description),lower(coalesce(payload->>'description','')))>0
   and strpos(lower(e.tags_text),lower(coalesce(payload->>'tags','')))>0
   and strpos(lower(concat_ws(' ',e.effective_description,e.account_name,e.category_name,e.tags_text,e.notes)),lower(coalesce(payload->>'query','')))>0
 ), ordered as (
  select *,row_number() over(order by
   case when _sort='date' and _direction='asc' then date end asc,
   case when _sort='date' and _direction='desc' then date end desc,
   case when _sort='amount' and _direction='asc' then amount_minor end asc,
   case when _sort='amount' and _direction='desc' then amount_minor end desc,
   case when _direction='asc' then case _sort when 'description' then lower(effective_description) when 'account' then lower(account_name) when 'category' then lower(coalesce(category_name,'')) when 'tags' then lower(tags_text) end end asc,
   case when _direction='desc' then case _sort when 'description' then lower(effective_description) when 'account' then lower(account_name) when 'category' then lower(coalesce(category_name,'')) when 'tags' then lower(tags_text) end end desc,
   id asc) as position from filtered
 )
 select jsonb_build_object('total',(select count(*) from filtered),'limit',_limit,'offset',_offset,'trash_total',(select count(*) from household_private.transactions where deleted_at is not null),'rows',
  coalesce((select jsonb_agg(row_data order by position) from ordered where position>_offset and position<=_offset+_limit),'[]'::jsonb)) into result;
 return result;
end $$;


create or replace function household_private.ledger_update(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();t household_private.transactions;target uuid;override_description text;new_tags text[];new_review text;
begin
 select * into t from household_private.transactions where id=(payload->>'id')::uuid for update;
 if t.id is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 if t.deleted_at is not null then raise exception using errcode='40001',message='Restore the transaction before editing';end if;
 if t.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Transaction changed; refresh before saving';end if;
 override_description:=case when payload?'description_override' then nullif(btrim(payload->>'description_override'),'') else t.description_override end;
 if payload?'description_override' and payload->'description_override'<>'null'::jsonb and (override_description is null or length(override_description)>500) then
  raise exception using errcode='22023',message='Description must contain 1–500 characters';end if;
 target:=case when payload?'account_override_id' then (payload->>'account_override_id')::uuid else t.account_override_id end;
 if target is not null and not exists(select 1 from household_private.accounts destination join household_private.accounts original on original.id=t.account_id
  where destination.id=target and destination.currency=original.currency) then
  raise exception using errcode='22023',message='Choose an existing account with the same currency';end if;
 if payload?'notes' and (jsonb_typeof(payload->'notes') not in ('string','null') or length(coalesce(payload->>'notes',''))>10000) then raise exception using errcode='22023',message='Notes must be text up to 10000 characters';end if;
 if payload?'needs_attention' and jsonb_typeof(payload->'needs_attention')<>'boolean' then raise exception using errcode='22023',message='Invalid attention flag';end if;
 new_review:=case when payload?'review_status' then payload->>'review_status' else t.review_status end;
 if new_review is null or new_review not in ('unreviewed','reviewed') then raise exception using errcode='22023',message='Invalid review status';end if;
 new_tags:=t.tags_override;
 if payload?'tags_override' then
  if payload->'tags_override'='null'::jsonb then new_tags:=null;
  else
   if jsonb_typeof(payload->'tags_override')<>'array' or jsonb_array_length(payload->'tags_override')>20 then raise exception using errcode='22023',message='Use up to 20 tags';end if;
   if exists(select 1 from jsonb_array_elements(payload->'tags_override') v where jsonb_typeof(v)<>'string' or length(btrim(v#>>'{}')) not between 1 and 60) then raise exception using errcode='22023',message='Tag labels must contain 1–60 characters';end if;
   select coalesce(array_agg(btrim(value)),'{}'::text[]) into new_tags from jsonb_array_elements_text(payload->'tags_override');
   if cardinality(new_tags)<>(select count(distinct lower(x)) from unnest(new_tags) x) then raise exception using errcode='22023',message='Repeated tag labels';end if;
  end if;
 end if;
 update household_private.transactions set description_override=override_description,account_override_id=target,
  notes=case when payload?'notes' then coalesce(payload->>'notes','') else notes end,tags_override=new_tags,
  needs_attention=case when payload?'needs_attention' then (payload->>'needs_attention')::boolean else needs_attention end,
  reviewed_at=case when new_review='unreviewed' then null when t.review_status<>'reviewed' then now() else t.reviewed_at end,
  reviewed_by=case when new_review='unreviewed' then null when t.review_status<>'reviewed' then actor else t.reviewed_by end,review_status=new_review,
  category_id=case when payload?'category_id' then (payload->>'category_id')::uuid else category_id end,revision=revision+1 where id=t.id;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,'edit_transaction_overrides',t.id);
 return jsonb_build_object('id',t.id,'revision',t.revision+1);
end $$;

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
   where deleted_at is null and (payload->>'account_id' is null or account_id=(payload->>'account_id')::uuid)
    and (payload->>'property_id' is null or property_id=(payload->>'property_id')::uuid)
   order by date desc,id limit limit_count offset offset_count
  ) t; return result;
 elsif operation='assign_transaction' then
  update household_private.transactions set property_id=(payload->>'property_id')::uuid,category_id=(payload->>'category_id')::uuid,revision=revision+1
   where deleted_at is null and id=(payload->>'id')::uuid and revision=(payload->>'revision')::integer returning to_jsonb(transactions.*) into result;
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


create or replace function household_private.entry_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
 if operation='get_transaction_detail' then return household_private.transaction_detail(payload);end if;
 if operation='trash_transaction' then return household_private.transaction_trash(payload,false);end if;
 if operation='restore_transaction' then return household_private.transaction_trash(payload,true);end if;
 if operation in ('prepare_receipt','finish_receipt_upload','finish_receipt_removal') then return household_private.receipt_action(operation,payload);end if;
 if operation='list_ledger_transactions' then return household_private.ledger_query(payload);end if;
 if operation='update_ledger_transaction' then return household_private.ledger_update(payload);end if;
 if operation in ('stage_monarch_snapshot','commit_monarch_snapshot','list_source_snapshots') then
  actor_role:=household_private.member_role();
  if operation='list_source_snapshots' then
   select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'source',s.source,'account_name',s.payload->'account'->>'name','period_start',s.period_start,'period_end',s.period_end,
    'created_at',s.created_at,'committed_at',s.committed_at,'inserted_count',s.inserted_count,'skipped_count',s.skipped_count,'expected_count',s.payload->'expected_count',
    'coverage_notes',s.payload->'coverage_notes','created_via',s.created_via) order by s.created_at desc),'[]'::jsonb) into result from household_private.source_snapshots s;
   return result;
  end if;
  if actor_role<>'owner' then raise exception using errcode='42501',message='Owner required for source imports';end if;
  if operation='stage_monarch_snapshot' then ident:=household_private.monarch_stage(payload,actor,'browser');return jsonb_build_object('id',ident,'status','staged');end if;
  return household_private.monarch_commit((payload->>'id')::uuid,actor);
 end if;
 result:=household_private.v1(operation,payload);
 if operation in ('access_state','request_access') then
  result:=result||jsonb_build_object('passkey_verified',exists(select 1 from auth.mfa_amr_claims a where a.session_id=nullif(auth.jwt()->>'session_id','')::uuid and a.authentication_method='passkey'));
 end if;
 return result;
end $$;


notify pgrst,'reload schema';
