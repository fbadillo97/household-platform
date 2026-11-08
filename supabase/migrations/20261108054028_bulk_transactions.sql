create function household_private.bulk_transactions(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();
 action text:=payload->>'action';items jsonb:=payload->'items';value jsonb:=payload->'value';item jsonb;row_data record;
 requested integer;locked integer;changed integer:=0;tags text[];label text;patch jsonb;different boolean;category uuid;
begin
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>20000 then raise exception using errcode='22023',message='Invalid bulk request';end if;
 if action is null or action not in ('category','review','attention','add_tag','remove_tag','trash','restore') then raise exception using errcode='22023',message='Choose a supported bulk action';end if;
 if jsonb_typeof(items) is distinct from 'array' then raise exception using errcode='22023',message='Select transactions on the current page';end if;
 requested:=jsonb_array_length(items);
 if requested not between 1 and 50 then raise exception using errcode='22023',message='Select between 1 and 50 transactions';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in ('items','action','value')) then raise exception using errcode='22023',message='Unsupported bulk request field';end if;
 for item in select v from jsonb_array_elements(items) v loop
  if jsonb_typeof(item) is distinct from 'object' then raise exception using errcode='22023',message='Each selection needs an ID and revision';end if;
  if jsonb_typeof(item->'id') is distinct from 'string' or coalesce(item->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or jsonb_typeof(item->'revision') is distinct from 'number' or coalesce(item->>'revision','') !~ '^[1-9][0-9]{0,8}$'
   or exists(select 1 from jsonb_object_keys(item) k where k not in ('id','revision')) then raise exception using errcode='22023',message='Each selection needs a valid ID and revision';end if;
 end loop;
 if (select count(distinct (v->>'id')::uuid) from jsonb_array_elements(items) v)<>requested then raise exception using errcode='22023',message='Repeated transaction selection';end if;
 if action='category' then
  if value is null or jsonb_typeof(value) not in ('string','null') then raise exception using errcode='22023',message='Choose a category or Unassigned';end if;
  if value<>'null'::jsonb then
   if (value#>>'{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception using errcode='22023',message='Invalid category';end if;
   category:=(value#>>'{}')::uuid;
   if not exists(select 1 from household_private.categories c where c.id=category) then raise exception using errcode='22023',message='Category no longer exists';end if;
  end if;
 elsif action='review' then
  if jsonb_typeof(value) is distinct from 'string' or (value#>>'{}') not in ('reviewed','unreviewed') then raise exception using errcode='22023',message='Choose reviewed or unreviewed';end if;
 elsif action='attention' then
  if jsonb_typeof(value) is distinct from 'boolean' then raise exception using errcode='22023',message='Choose an attention status';end if;
 elsif action in ('add_tag','remove_tag') then
  if jsonb_typeof(value) is distinct from 'string' or length(btrim(value#>>'{}')) not between 1 and 60 then raise exception using errcode='22023',message='Use a tag containing 1–60 characters';end if;
  label:=btrim(value#>>'{}');
 end if;
 -- Lock the entire selection before validating revisions/states or changing any row.
 perform 1 from household_private.transactions t where t.id in (select (v->>'id')::uuid from jsonb_array_elements(items) v) order by t.id for update;
 get diagnostics locked=row_count;
 if locked<>requested then raise exception using errcode='P0002',message='A selected transaction no longer exists; refresh and select again. Nothing was changed';end if;
 if exists(select 1 from household_private.transactions t join jsonb_array_elements(items) v on t.id=(v->>'id')::uuid where t.revision<>(v->>'revision')::integer) then
  raise exception using errcode='40001',message='A selected transaction changed; refresh and select again. Nothing was changed';end if;
 if exists(select 1 from household_private.transactions t join jsonb_array_elements(items) v on t.id=(v->>'id')::uuid where (action='restore' and t.deleted_at is null) or (action<>'restore' and t.deleted_at is not null)) then
  raise exception using errcode='40001',message='A selected transaction moved into or out of Trash; refresh and select again. Nothing was changed';end if;
 if action='trash' and exists(select 1 from household_private.transactions t join jsonb_array_elements(items) v on t.id=(v->>'id')::uuid where t.transfer_peer_id is not null) then
  raise exception using errcode='40001',message='Unlink or deselect linked transfers before bulk Trash. Nothing was changed';end if;
 for row_data in select t.* from household_private.transactions t join jsonb_array_elements(items) v on t.id=(v->>'id')::uuid order by t.id loop
  patch:=jsonb_build_object('id',row_data.id,'revision',row_data.revision);different:=true;
  if action='category' then patch:=patch||jsonb_build_object('category_id',category);different:=row_data.category_id is distinct from category;
  elsif action='review' then patch:=patch||jsonb_build_object('review_status',value);different:=row_data.review_status is distinct from value#>>'{}';
  elsif action='attention' then patch:=patch||jsonb_build_object('needs_attention',value);different:=row_data.needs_attention is distinct from (value#>>'{}')::boolean;
  elsif action in ('add_tag','remove_tag') then
   -- Preserve effective tag labels and their order. Imported metadata remains unchanged.
   select coalesce(array_agg(name order by position),'{}'::text[]) into tags from (
    select btrim(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end) name,position
    from jsonb_array_elements(case when row_data.tags_override is not null then to_jsonb(row_data.tags_override) when jsonb_typeof(row_data.source_data->'tags')='array' then row_data.source_data->'tags' else '[]'::jsonb end) with ordinality v(tag,position)
   ) names where name<>'';
   if action='add_tag' then
    different:=not exists(select 1 from unnest(tags) name where lower(name)=lower(label));
    if different then tags:=array_append(tags,label);end if;
   else
    different:=exists(select 1 from unnest(tags) name where lower(name)=lower(label));
    select coalesce(array_agg(name order by position),'{}'::text[]) into tags from unnest(tags) with ordinality v(name,position) where lower(name)<>lower(label);
   end if;
   patch:=patch||jsonb_build_object('tags_override',tags);
  end if;
  if different then
   if action='trash' then perform household_private.transaction_trash(patch,false);
   elsif action='restore' then perform household_private.transaction_trash(patch,true);
   else perform household_private.ledger_update(patch);end if;
   insert into household_private.audit_events(actor_id,action,target_id) values(actor,'bulk_'||action,row_data.id);
   changed:=changed+1;
  end if;
 end loop;
 return jsonb_build_object('selected_count',requested,'updated_count',changed,'action',action);
end $$;
revoke all on function household_private.bulk_transactions(jsonb) from public,anon,authenticated;

create or replace function household_private.entry_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
 if operation='bulk_update_transactions' then return household_private.bulk_transactions(payload);end if;
 if operation='list_transfer_candidates' then return household_private.transfer_candidates(payload);end if;
 if operation in ('set_transaction_flow','link_transfer','unlink_transfer') then return household_private.transfer_action(operation,payload);end if;
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
