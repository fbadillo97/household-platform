-- Payees are counterparties, independent of category/accounting and imported originals.
create function household_private.payee_key(value text) returns text
language sql immutable strict set search_path='' as $$
 select lower(regexp_replace(btrim(value),'\s+',' ','g'));
$$;
create table household_private.payees(
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 120),
 kind text not null default 'other' check(kind in ('business','institution','person','other')),
 archived_at timestamptz,
 revision integer not null default 1,
 created_at timestamptz not null default now()
);
create unique index payees_name_key on household_private.payees(household_private.payee_key(name));
create table household_private.payee_aliases(
 id uuid primary key default gen_random_uuid(),
 payee_id uuid not null references household_private.payees(id),
 description text not null check(length(btrim(description)) between 1 and 500),
 match_key text generated always as (household_private.payee_key(description)) stored unique
);
create index payee_aliases_payee_idx on household_private.payee_aliases(payee_id);
alter table household_private.payees enable row level security;
alter table household_private.payee_aliases enable row level security;
revoke all on household_private.payees,household_private.payee_aliases from public,anon,authenticated;
alter table household_private.transactions
 add column payee_id uuid references household_private.payees(id),
 add column payee_assignment text check(payee_assignment in ('manual','alias'));
create index transactions_payee_idx on household_private.transactions(payee_id);

create function household_private.payee_list() returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();result jsonb;
begin
 if (select count(*) from household_private.payees)>2000 then
  raise exception using errcode='54000',message='Payee directory exceeds 2000 entries; contact the administrator';end if;
 select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('aliases',
  coalesce((select jsonb_agg(a.description order by a.match_key) from household_private.payee_aliases a where a.payee_id=p.id),'[]'::jsonb)) order by lower(p.name),p.id),'[]'::jsonb)
 into result from household_private.payees p;
 return result;
end $$;

create function household_private.payee_action(operation text,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();
 ident uuid;p household_private.payees;t household_private.transactions;label text;_kind text;aliases jsonb;result jsonb;
begin
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>40000 then
  raise exception using errcode='22023',message='Invalid payee request';end if;
 if operation='remember_payee_alias' then
  select * into t from household_private.transactions where id=(payload->>'id')::uuid for share;
  if t.id is null or t.deleted_at is not null or t.revision is distinct from (payload->>'revision')::integer or t.payee_id is null then
   raise exception using errcode='40001',message='Transaction changed; reload before remembering a payee';end if;
  select * into p from household_private.payees where id=t.payee_id for update;
  if p.archived_at is not null then raise exception using errcode='22023',message='Restore the payee before adding an alias';end if;
  if exists(select 1 from household_private.payee_aliases a where a.match_key=household_private.payee_key(t.description) and a.payee_id<>p.id) then
   raise exception using errcode='22023',message='This imported description belongs to another payee alias';end if;
  if not exists(select 1 from household_private.payee_aliases a where a.match_key=household_private.payee_key(t.description)) then
   if (select count(*) from household_private.payee_aliases where payee_id=p.id)>=50 then
    raise exception using errcode='22023',message='Use up to 50 aliases per payee';end if;
   insert into household_private.payee_aliases(payee_id,description) values(p.id,t.description);
   update household_private.payees set revision=revision+1 where id=p.id;
   insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,p.id);
  end if;
  return jsonb_build_object('id',p.id);
 end if;
 if operation not in ('create_payee','update_payee') then raise exception using errcode='22023',message='Unknown payee operation';end if;
 if jsonb_typeof(payload->'name') is distinct from 'string' or length(btrim(payload->>'name')) not between 1 and 120 then
  raise exception using errcode='22023',message='Payee name must contain 1–120 characters';end if;
 label:=btrim(payload->>'name');_kind:=coalesce(payload->>'kind','other');
 if _kind not in ('business','institution','person','other') then raise exception using errcode='22023',message='Choose a valid payee kind';end if;
 aliases:=coalesce(payload->'aliases','[]'::jsonb);
 if jsonb_typeof(aliases)<>'array' or jsonb_array_length(aliases)>50 then raise exception using errcode='22023',message='Use up to 50 aliases';end if;
 if exists(select 1 from jsonb_array_elements(aliases) v where jsonb_typeof(v)<>'string' or length(btrim(v#>>'{}')) not between 1 and 500) then
  raise exception using errcode='22023',message='Each alias must contain 1–500 characters';end if;
 if jsonb_array_length(aliases)<>(select count(distinct household_private.payee_key(v)) from jsonb_array_elements_text(aliases) v) then
  raise exception using errcode='22023',message='Repeated aliases; use each imported description once';end if;
 if operation='create_payee' then
  if (select count(*) from household_private.payees)>=2000 then raise exception using errcode='54000',message='Payee directory limit reached';end if;
  insert into household_private.payees(name,kind) values(label,_kind) returning id into ident;
 else
  ident:=(payload->>'id')::uuid;
  select * into p from household_private.payees where id=ident for update;
  if p.id is null or p.revision is distinct from (payload->>'revision')::integer then
   raise exception using errcode='40001',message='Payee changed; reload before saving';end if;
  if payload?'archived' and jsonb_typeof(payload->'archived')<>'boolean' then raise exception using errcode='22023',message='Invalid archive flag';end if;
  update household_private.payees set name=label,kind=_kind,revision=revision+1,
   archived_at=case when coalesce((payload->>'archived')::boolean,p.archived_at is not null) then coalesce(p.archived_at,now()) else null end where id=ident;
 end if;
 if exists(select 1 from household_private.payee_aliases a where a.payee_id<>ident and a.match_key in (select household_private.payee_key(v) from jsonb_array_elements_text(aliases) v)) then
  raise exception using errcode='22023',message='An alias already belongs to another payee';end if;
 delete from household_private.payee_aliases where payee_id=ident;
 insert into household_private.payee_aliases(payee_id,description) select ident,btrim(value) from jsonb_array_elements_text(aliases);
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);
 return jsonb_build_object('id',ident);
exception when unique_violation then
 raise exception using errcode='22023',message='Payee name or alias already exists; choose a unique name and description';
end $$;

-- Exact aliases affect new records only; deployment never backfills existing transactions.
create function household_private.recognize_payee() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.payee_id is null and new.payee_assignment is null then
  select a.payee_id into new.payee_id from household_private.payee_aliases a
   join household_private.payees p on p.id=a.payee_id
   where a.match_key=household_private.payee_key(new.description) and p.archived_at is null;
  if new.payee_id is not null then new.payee_assignment:='alias';end if;
 end if;
 return new;
end $$;
create trigger recognize_payee_on_import before insert on household_private.transactions
 for each row execute function household_private.recognize_payee();


CREATE OR REPLACE FUNCTION household_private.ledger_query(payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 _role text:=household_private.member_role();_limit integer:=coalesce((payload->>'limit')::integer,50);_offset integer:=coalesce((payload->>'offset')::integer,0);
 _sort text:=coalesce(payload->>'sort','date');_direction text:=coalesce(payload->>'direction','desc');_trash boolean:=coalesce((payload->>'trash_only')::boolean,false);_review text:=coalesce(payload->>'review','');_flow text:=coalesce(payload->>'flow','');
 _account uuid:=nullif(payload->>'account_id','')::uuid;_payee uuid:=nullif(nullif(payload->>'payee_id','__unassigned'),'')::uuid;_category uuid:=nullif(nullif(payload->>'category_id','__unassigned'),'')::uuid;
 _from date:=(payload->>'date_from')::date;_to date:=(payload->>'date_to')::date;
 _min bigint:=(payload->>'min_minor')::bigint;_max bigint:=(payload->>'max_minor')::bigint;result jsonb;
begin
 if _limit not between 1 and 500 or _offset not between 0 and 1000000 or _sort not in ('date','description','account','amount','category','tags','payee') or _direction not in ('asc','desc') then
  raise exception using errcode='22023',message='Invalid sort or pagination';end if;
 if _flow not in ('','regular','transfer','credit_card_payment','unlinked_transfer') then raise exception using errcode='22023',message='Invalid transaction type filter';end if;
 if _review not in ('','unreviewed','reviewed','needs_attention') then raise exception using errcode='22023',message='Invalid review filter';end if;
 if (_from is not null and _to is not null and _from>_to) or (_min is not null and _max is not null and _min>_max)
  or coalesce(payload->>'month','') !~ '^([0-9]{4}-(0[1-9]|1[0-2]))?$'
  or length(coalesce(payload->>'query',''))>500 or length(coalesce(payload->>'description',''))>500 or length(coalesce(payload->>'tags',''))>200 then
  raise exception using errcode='22023',message='Check the date, amount or text filters';end if;
 with effective as (
  select t.id,t.date,t.amount_minor,t.category_id,t.payee_id,t.flow_type,t.transfer_peer_id,t.notes,t.review_status,t.needs_attention,t.deleted_at,coalesce(t.account_override_id,t.account_id) as effective_account,
   coalesce(t.description_override,t.description) as effective_description,a.name as account_name,c.name as category_name,p.name as payee_name,tag_names.terms as tags_text,
   to_jsonb(t)||jsonb_build_object('description',coalesce(t.description_override,t.description),'account_id',coalesce(t.account_override_id,t.account_id),
    'original_description',t.description,'original_account_id',t.account_id,'account_name',a.name,'category_name',c.name,'payee_name',p.name,'tags_text',tag_names.terms,
    'receipt_count',(select count(*) from household_private.receipts r where r.transaction_id=t.id and r.state='ready' and r.removed_at is null),'has_description_override',t.description_override is not null,'has_account_override',t.account_override_id is not null) as row_data
  from household_private.transactions t
  join household_private.accounts a on a.id=coalesce(t.account_override_id,t.account_id)
  left join household_private.categories c on c.id=t.category_id
  left join household_private.payees p on p.id=t.payee_id
  left join lateral(select coalesce(string_agg(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end,' '),'') as terms
   from jsonb_array_elements(case when t.tags_override is not null then to_jsonb(t.tags_override) when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) tag) tag_names on true
 ), filtered as (
  select * from effective e where ((_trash and e.deleted_at is not null) or (not _trash and e.deleted_at is null))
   and (_flow='' or (_flow='unlinked_transfer' and e.flow_type<>'regular' and e.transfer_peer_id is null) or e.flow_type=_flow)
   and (_review='' or (_review='needs_attention' and e.needs_attention) or e.review_status=_review) and (_account is null or e.effective_account=_account)
   and (coalesce(payload->>'category_id','')<>'__unassigned' or e.category_id is null) and (_category is null or e.category_id=_category)
   and (coalesce(payload->>'payee_id','')<>'__unassigned' or e.payee_id is null) and (_payee is null or e.payee_id=_payee)
   and (_from is null or e.date>=_from) and (_to is null or e.date<=_to)
   and (coalesce(payload->>'month','')='' or to_char(e.date,'YYYY-MM')=payload->>'month')
   and (_min is null or e.amount_minor>=_min) and (_max is null or e.amount_minor<=_max)
   and strpos(lower(e.effective_description),lower(coalesce(payload->>'description','')))>0
   and strpos(lower(e.tags_text),lower(coalesce(payload->>'tags','')))>0
   and strpos(lower(concat_ws(' ',e.effective_description,e.account_name,e.category_name,e.payee_name,e.tags_text,e.notes)),lower(coalesce(payload->>'query','')))>0
 ), ordered as (
  select *,row_number() over(order by
   case when _sort='date' and _direction='asc' then date end asc,
   case when _sort='date' and _direction='desc' then date end desc,
   case when _sort='amount' and _direction='asc' then amount_minor end asc,
   case when _sort='amount' and _direction='desc' then amount_minor end desc,
   case when _direction='asc' then case _sort when 'description' then lower(effective_description) when 'account' then lower(account_name) when 'category' then lower(coalesce(category_name,'')) when 'payee' then lower(coalesce(payee_name,'')) when 'tags' then lower(tags_text) end end asc,
   case when _direction='desc' then case _sort when 'description' then lower(effective_description) when 'account' then lower(account_name) when 'category' then lower(coalesce(category_name,'')) when 'payee' then lower(coalesce(payee_name,'')) when 'tags' then lower(tags_text) end end desc,
   id asc) as position from filtered
 )
 select jsonb_build_object('total',(select count(*) from filtered),'limit',_limit,'offset',_offset,'trash_total',(select count(*) from household_private.transactions where deleted_at is not null),'rows',
  coalesce((select jsonb_agg(row_data order by position) from ordered where position>_offset and position<=_offset+_limit),'[]'::jsonb)) into result;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION household_private.ledger_update(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();t household_private.transactions;target uuid;override_description text;new_tags text[];new_review text;new_payee uuid;
begin
 select * into t from household_private.transactions where id=(payload->>'id')::uuid for update;
 if t.id is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 if t.deleted_at is not null then raise exception using errcode='40001',message='Restore the transaction before editing';end if;
 if t.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Transaction changed; refresh before saving';end if;
 new_payee:=case when payload?'payee_id' then (payload->>'payee_id')::uuid else t.payee_id end;
 if new_payee is not null and new_payee is distinct from t.payee_id then
  perform 1 from household_private.payees where id=new_payee and archived_at is null for share;
  if not found then raise exception using errcode='22023',message='Choose an active payee';end if;
 end if;
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
 update household_private.transactions set payee_id=new_payee,payee_assignment=case when payload?'payee_id' then 'manual' else payee_assignment end,description_override=override_description,account_override_id=target,
  notes=case when payload?'notes' then coalesce(payload->>'notes','') else notes end,tags_override=new_tags,
  needs_attention=case when payload?'needs_attention' then (payload->>'needs_attention')::boolean else needs_attention end,
  reviewed_at=case when new_review='unreviewed' then null when t.review_status<>'reviewed' then now() else t.reviewed_at end,
  reviewed_by=case when new_review='unreviewed' then null when t.review_status<>'reviewed' then actor else t.reviewed_by end,review_status=new_review,
  category_id=case when payload?'category_id' then (payload->>'category_id')::uuid else category_id end,revision=revision+1 where id=t.id;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,'edit_transaction_overrides',t.id);
 return jsonb_build_object('id',t.id,'revision',t.revision+1);
end $function$;

CREATE OR REPLACE FUNCTION household_private.transaction_detail(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare _role text:=household_private.member_role();result jsonb;
begin
 select to_jsonb(t)||jsonb_build_object('description',coalesce(t.description_override,t.description),'account_id',coalesce(t.account_override_id,t.account_id),
  'transfer_peer',(select jsonb_build_object('id',p.id,'revision',p.revision,'date',p.date,'description',coalesce(p.description_override,p.description),'account_id',coalesce(p.account_override_id,p.account_id),'amount_minor',p.amount_minor) from household_private.transactions p where p.id=t.transfer_peer_id),
  'suggested_payee_id',case when t.payee_id is null and t.payee_assignment is null then
   (select a.payee_id from household_private.payee_aliases a join household_private.payees p on p.id=a.payee_id
    where a.match_key=household_private.payee_key(t.description) and p.archived_at is null) else null end,
  'original_description',t.description,'original_account_id',t.account_id,
  'original_tags',coalesce((select jsonb_agg(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end)
   from jsonb_array_elements(case when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) tag),'[]'::jsonb),
  'receipts',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from household_private.receipts r where r.transaction_id=t.id and r.removed_at is null),'[]'::jsonb)) into result
  from household_private.transactions t where t.id=(payload->>'id')::uuid;
 if result is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION household_private.entry_v1(operation text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
 if operation='list_payees' then return household_private.payee_list();end if;
 if operation in ('create_payee','update_payee','remember_payee_alias') then return household_private.payee_action(operation,payload);end if;
 if operation='update_category_behavior' then return household_private.category_behavior_action(payload);end if;
 if operation='get_balance_history' then return household_private.balance_history(payload);end if;
 if operation='list_accounts' then return household_private.account_list();end if;
 if operation in ('create_account','update_account','archive_account','restore_account','save_account_balance') then return household_private.account_action(operation,payload);end if;
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
end $function$;

revoke all on function household_private.payee_key(text),household_private.payee_list(),household_private.payee_action(text,jsonb),household_private.recognize_payee() from public,anon,authenticated;
notify pgrst,'reload schema';
CREATE OR REPLACE FUNCTION household_private.bulk_transactions(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();
 action text:=payload->>'action';items jsonb:=payload->'items';value jsonb:=payload->'value';item jsonb;row_data record;
 requested integer;locked integer;changed integer:=0;tags text[];label text;patch jsonb;different boolean;category uuid;
begin
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>20000 then raise exception using errcode='22023',message='Invalid bulk request';end if;
 if action is null or action not in ('category','payee','review','attention','add_tag','remove_tag','trash','restore') then raise exception using errcode='22023',message='Choose a supported bulk action';end if;
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
 elsif action='payee' then
  if value is null or jsonb_typeof(value) not in ('string','null') then raise exception using errcode='22023',message='Choose a payee or Unassigned';end if;
  if value<>'null'::jsonb then
   category:=(value#>>'{}')::uuid;
   if not exists(select 1 from household_private.payees p where p.id=category and p.archived_at is null) then raise exception using errcode='22023',message='Choose an active payee';end if;
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
  elsif action='payee' then patch:=patch||jsonb_build_object('payee_id',category);different:=row_data.payee_id is distinct from category;
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
end $function$;
