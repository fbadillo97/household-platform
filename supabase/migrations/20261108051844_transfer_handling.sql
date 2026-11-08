-- Local classification only: imported values, categories and source identities are unchanged.
alter table household_private.transactions add column flow_type text not null default 'regular' check(flow_type in ('regular','transfer','credit_card_payment'));
alter table household_private.transactions add column transfer_peer_id uuid unique references household_private.transactions(id);
alter table household_private.transactions add constraint transfer_peer_valid check(transfer_peer_id is null or (transfer_peer_id<>id and flow_type<>'regular'));
create index transactions_transfer_candidates_idx on household_private.transactions(amount_minor,date) where deleted_at is null and transfer_peer_id is null;

create function household_private.transfer_candidates(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();t household_private.transactions;days integer:=coalesce((payload->>'days')::integer,7);q text:=btrim(coalesce(payload->>'query',''));result jsonb;
begin
 if days not in (7,31) or length(q)>500 then raise exception using errcode='22023',message='Choose a 7 or 31 day matching window';end if;
 select * into t from household_private.transactions where id=(payload->>'id')::uuid;
 if t.id is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 if t.deleted_at is not null or t.transfer_peer_id is not null or t.amount_minor=0 then return jsonb_build_object('rows','[]'::jsonb,'total',0,'days',days);end if;
 with matches as (
  select x.id,x.revision,x.date,coalesce(x.description_override,x.description) description,x.amount_minor,
   coalesce(x.account_override_id,x.account_id) account_id,a.name account_name,a.currency,x.flow_type,
   case when (t.amount_minor<0 and original.kind<>'credit' and a.kind='credit') or (x.amount_minor<0 and a.kind<>'credit' and original.kind='credit') then 'credit_card_payment' else 'transfer' end suggested_type,
   abs(x.date-t.date) distance
  from household_private.transactions x
  join household_private.accounts a on a.id=coalesce(x.account_override_id,x.account_id)
  join household_private.accounts original on original.id=coalesce(t.account_override_id,t.account_id)
  where x.id<>t.id and x.deleted_at is null and x.transfer_peer_id is null
   and x.amount_minor=-t.amount_minor and a.currency=original.currency and a.id<>original.id
   and x.date between t.date-days and t.date+days
   and strpos(lower(concat_ws(' ',coalesce(x.description_override,x.description),a.name)),lower(q))>0
 ) select jsonb_build_object('total',(select count(*) from matches),'days',days,'rows',coalesce((select jsonb_agg(to_jsonb(m)-'distance' order by distance,date,id) from (select * from matches order by distance,date,id limit 50) m),'[]'::jsonb)) into result;
 return result;
end $$;

create function household_private.transfer_action(operation text,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();
 ident uuid:=(payload->>'id')::uuid;peer uuid:=(payload->>'peer_id')::uuid;t household_private.transactions;p household_private.transactions;
 kind text:=payload->>'flow_type';a household_private.accounts;b household_private.accounts;
begin
 if operation not in ('set_transaction_flow','link_transfer','unlink_transfer') then raise exception using errcode='22023',message='Unknown transfer operation';end if;
 if ident is null or (operation<>'set_transaction_flow' and (peer is null or peer=ident)) then raise exception using errcode='22023',message='Choose two different transactions';end if;
 -- All pair mutations acquire transaction locks in UUID order, then recheck both revisions.
 perform 1 from household_private.transactions where id=ident or (operation<>'set_transaction_flow' and id=peer) order by id for update;
 select * into t from household_private.transactions where id=ident;
 if t.id is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 if t.deleted_at is not null then raise exception using errcode='40001',message='Restore the transaction before changing its transfer details';end if;
 if t.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Transaction changed; reload before continuing';end if;
 if operation='set_transaction_flow' then
  if t.transfer_peer_id is not null then raise exception using errcode='40001',message='Undo the linked transfer before changing its type';end if;
  if kind is null or kind not in ('regular','transfer','credit_card_payment') or (kind<>'regular' and t.amount_minor=0) then raise exception using errcode='22023',message='Choose a valid transaction type';end if;
  select * into a from household_private.accounts where id=coalesce(t.account_override_id,t.account_id);
  if kind='credit_card_payment' and not ((a.kind='credit' and t.amount_minor>0) or (a.kind<>'credit' and t.amount_minor<0)) then raise exception using errcode='22023',message='A card payment must leave a funding account or arrive on a credit card';end if;
  update household_private.transactions set flow_type=kind,revision=revision+1 where id=ident;
 else
  select * into p from household_private.transactions where id=peer;
  if p.id is null then raise exception using errcode='P0002',message='Other transaction not found';end if;
  if p.deleted_at is not null or p.revision is distinct from (payload->>'peer_revision')::integer then raise exception using errcode='40001',message='Other transaction changed; reload the matches';end if;
  if operation='link_transfer' then
   if t.transfer_peer_id is not null or p.transfer_peer_id is not null then raise exception using errcode='40001',message='A transaction is already linked; reload the matches';end if;
   select * into a from household_private.accounts where id=coalesce(t.account_override_id,t.account_id);
   select * into b from household_private.accounts where id=coalesce(p.account_override_id,p.account_id);
   if kind is null or kind not in ('transfer','credit_card_payment') or t.amount_minor=0 or t.amount_minor<>-p.amount_minor or a.id=b.id or a.currency<>b.currency or abs(t.date-p.date)>31 then
    raise exception using errcode='22023',message='Link equal and opposite amounts in different accounts, in the same currency, within 31 days';end if;
   if kind='credit_card_payment' and not ((t.amount_minor<0 and a.kind<>'credit' and b.kind='credit') or (p.amount_minor<0 and b.kind<>'credit' and a.kind='credit')) then raise exception using errcode='22023',message='Card payments must move from a funding account to a credit card';end if;
   update household_private.transactions set flow_type=kind,transfer_peer_id=case when id=ident then peer else ident end,revision=revision+1 where id in (ident,peer);
  else
   if t.transfer_peer_id is distinct from peer or p.transfer_peer_id is distinct from ident then raise exception using errcode='40001',message='The link changed; reload before continuing';end if;
   update household_private.transactions set flow_type='regular',transfer_peer_id=null,revision=revision+1 where id in (ident,peer);
  end if;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,peer);
 end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);
 return household_private.transaction_detail(jsonb_build_object('id',ident));
end $$;
revoke all on function household_private.transfer_candidates(jsonb),household_private.transfer_action(text,jsonb) from public,anon,authenticated;

create or replace function household_private.transaction_detail(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();result jsonb;
begin
 select to_jsonb(t)||jsonb_build_object('description',coalesce(t.description_override,t.description),'account_id',coalesce(t.account_override_id,t.account_id),
  'transfer_peer',(select jsonb_build_object('id',p.id,'revision',p.revision,'date',p.date,'description',coalesce(p.description_override,p.description),'account_id',coalesce(p.account_override_id,p.account_id),'amount_minor',p.amount_minor) from household_private.transactions p where p.id=t.transfer_peer_id),
  'original_description',t.description,'original_account_id',t.account_id,
  'original_tags',coalesce((select jsonb_agg(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end)
   from jsonb_array_elements(case when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) tag),'[]'::jsonb),
  'receipts',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from household_private.receipts r where r.transaction_id=t.id and r.removed_at is null),'[]'::jsonb)) into result
  from household_private.transactions t where t.id=(payload->>'id')::uuid;
 if result is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 return result;
end $$;

create or replace function household_private.transaction_trash(payload jsonb,restore boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();t household_private.transactions;
begin
 select * into t from household_private.transactions where id=(payload->>'id')::uuid for update;
 if t.id is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 if t.transfer_peer_id is not null then raise exception using errcode='40001',message='Undo the linked transfer before moving either side to Trash';end if;
 if t.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Transaction changed; reload before continuing';end if;
 if restore and t.deleted_at is null then raise exception using errcode='40001',message='Transaction is already active';end if;
 if not restore and t.deleted_at is not null then raise exception using errcode='40001',message='Transaction is already in Trash';end if;
 update household_private.transactions set deleted_at=case when restore then null else now() end,deleted_by=case when restore then null else actor end,revision=revision+1 where id=t.id;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,case when restore then 'restore_transaction' else 'trash_transaction' end,t.id);
 return household_private.transaction_detail(jsonb_build_object('id',t.id));
end $$;

create or replace function household_private.ledger_query(payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 _role text:=household_private.member_role();_limit integer:=coalesce((payload->>'limit')::integer,50);_offset integer:=coalesce((payload->>'offset')::integer,0);
 _sort text:=coalesce(payload->>'sort','date');_direction text:=coalesce(payload->>'direction','desc');_trash boolean:=coalesce((payload->>'trash_only')::boolean,false);_review text:=coalesce(payload->>'review','');_flow text:=coalesce(payload->>'flow','');
 _account uuid:=nullif(payload->>'account_id','')::uuid;_category uuid:=nullif(nullif(payload->>'category_id','__unassigned'),'')::uuid;
 _from date:=(payload->>'date_from')::date;_to date:=(payload->>'date_to')::date;
 _min bigint:=(payload->>'min_minor')::bigint;_max bigint:=(payload->>'max_minor')::bigint;result jsonb;
begin
 if _limit not between 1 and 500 or _offset not between 0 and 1000000 or _sort not in ('date','description','account','amount','category','tags') or _direction not in ('asc','desc') then
  raise exception using errcode='22023',message='Invalid sort or pagination';end if;
 if _flow not in ('','regular','transfer','credit_card_payment','unlinked_transfer') then raise exception using errcode='22023',message='Invalid transaction type filter';end if;
 if _review not in ('','unreviewed','reviewed','needs_attention') then raise exception using errcode='22023',message='Invalid review filter';end if;
 if (_from is not null and _to is not null and _from>_to) or (_min is not null and _max is not null and _min>_max)
  or coalesce(payload->>'month','') !~ '^([0-9]{4}-(0[1-9]|1[0-2]))?$'
  or length(coalesce(payload->>'query',''))>500 or length(coalesce(payload->>'description',''))>500 or length(coalesce(payload->>'tags',''))>200 then
  raise exception using errcode='22023',message='Check the date, amount or text filters';end if;
 with effective as (
  select t.id,t.date,t.amount_minor,t.category_id,t.flow_type,t.transfer_peer_id,t.notes,t.review_status,t.needs_attention,t.deleted_at,coalesce(t.account_override_id,t.account_id) as effective_account,
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
   and (_flow='' or (_flow='unlinked_transfer' and e.flow_type<>'regular' and e.transfer_peer_id is null) or e.flow_type=_flow)
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
 if t.transfer_peer_id is not null and coalesce(target,t.account_id)<>coalesce(t.account_override_id,t.account_id) then raise exception using errcode='40001',message='Undo the linked transfer before changing its account';end if;
 if t.flow_type='credit_card_payment' and not exists(select 1 from household_private.accounts a where a.id=coalesce(target,t.account_id) and ((a.kind='credit' and t.amount_minor>0) or (a.kind<>'credit' and t.amount_minor<0))) then raise exception using errcode='22023',message='Reset the card payment type before moving it to this account';end if;
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

create or replace function household_private.entry_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
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
