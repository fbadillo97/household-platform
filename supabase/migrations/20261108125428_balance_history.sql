-- Bounded, read-only history. Current inclusion settings define a constant cohort for the whole range.
create function household_private.balance_history(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();_scope text:=coalesce(payload->>'scope','net_worth');
 _currency text:=payload->>'currency';_account uuid;_from date;_to date:=current_date;earliest date;ids uuid[];result jsonb;entry_count integer;
begin
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>2000 then raise exception using errcode='22023',message='Invalid history request';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in ('scope','currency','account_id','from','to')) or _scope not in ('net_worth','account') then raise exception using errcode='22023',message='Choose a supported history view';end if;
 if _scope='account' then
  if jsonb_typeof(payload->'account_id') is distinct from 'string' or coalesce(payload->>'account_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception using errcode='22023',message='Choose an account';end if;
  _account:=(payload->>'account_id')::uuid;
  select currency into _currency from household_private.accounts where id=_account;
  if _currency is null then raise exception using errcode='P0002',message='Account not found';end if;
  if payload?'currency' and payload->>'currency' is distinct from _currency then raise exception using errcode='22023',message='History currency must match the account';end if;
  ids:=array[_account];
 else
  if jsonb_typeof(payload->'currency') is distinct from 'string' or coalesce(_currency,'') !~ '^[A-Z]{3}$' or payload?'account_id' then raise exception using errcode='22023',message='Choose one currency for net worth history';end if;
  select coalesce(array_agg(id),'{}'::uuid[]) into ids from (
   select id from household_private.accounts where currency=_currency and archived_at is null and include_in_net_worth order by id limit 501
  ) a;
  if cardinality(ids)>500 then raise exception using errcode='22023',message='Too many included accounts for history; open an individual account';end if;
 end if;
 if payload?'to' then
  if jsonb_typeof(payload->'to') is distinct from 'string' or payload->>'to' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception using errcode='22023',message='Use a valid end date';end if;
  begin _to:=(payload->>'to')::date;exception when datetime_field_overflow or invalid_datetime_format then raise exception using errcode='22023',message='Use a valid end date';end;
 end if;
 if _to<'1900-01-01' or _to>current_date then raise exception using errcode='22023',message='End date must be between 1900 and today';end if;
 select min(s.as_of) into earliest from unnest(ids) a(id) cross join lateral(
  select as_of from household_private.account_balance_snapshots where account_id=a.id and as_of<=_to order by as_of limit 1
 ) s;
 if not payload?'from' then _from:=_to-89;
 elsif payload->'from'='null'::jsonb then _from:=coalesce(earliest,_to);
 else
  if jsonb_typeof(payload->'from') is distinct from 'string' or payload->>'from' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception using errcode='22023',message='Use a valid start date';end if;
  begin _from:=(payload->>'from')::date;exception when datetime_field_overflow or invalid_datetime_format then raise exception using errcode='22023',message='Use a valid start date';end;
 end if;
 if _from<'1900-01-01' or _from>_to then raise exception using errcode='22023',message='Start date must not follow the end date or be before 1900';end if;
 -- Count effective dates, not discarded correction versions; never silently truncate a history.
 with effective as (
  select distinct on(s.account_id,s.as_of) s.account_id,s.as_of from household_private.account_balance_snapshots s
  where s.account_id=any(ids) and s.as_of between _from and _to order by s.account_id,s.as_of,s.sequence desc limit 10001
 ) select count(*) into entry_count from effective;
 if entry_count>10000 then raise exception using errcode='22023',message='History has too many saved dates; choose a shorter range';end if;
 with daily as (
  select distinct on(s.account_id,s.as_of) s.id,s.account_id,s.as_of,s.amount_minor,s.currency,s.is_estimate,
   case when _scope='account' then s.note else null end note,
   (count(*) over(partition by s.account_id,s.as_of))-1 correction_count,false carry_in
  from household_private.account_balance_snapshots s where s.account_id=any(ids) and s.as_of between _from and _to
  order by s.account_id,s.as_of,s.sequence desc
 ), seeds as (
  select s.id,s.account_id,s.as_of,s.amount_minor,s.currency,s.is_estimate,
   case when _scope='account' then s.note else null end note,
   (select count(*)-1 from household_private.account_balance_snapshots c where c.account_id=s.account_id and c.as_of=s.as_of) correction_count,true carry_in
  from unnest(ids) a(id) cross join lateral(
   select * from household_private.account_balance_snapshots where account_id=a.id and as_of<_from order by as_of desc,sequence desc limit 1
  ) s
 ), entries as (select * from daily union all select * from seeds)
 select jsonb_build_object('scope',_scope,'currency',_currency,'from',_from,'to',_to,'earliest_available',earliest,
  'cohort_policy',case when _scope='net_worth' then 'current_inclusion' else 'individual_account' end,
  'generated_at',now(),'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'kind',a.kind,'currency',a.currency,'include_in_net_worth',a.include_in_net_worth,'archived_at',a.archived_at) order by a.name,a.id) from household_private.accounts a where a.id=any(ids)),'[]'::jsonb),
  'entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.as_of,e.account_id) from entries e),'[]'::jsonb)) into result;
 if jsonb_array_length(result->'entries')>10000 or octet_length(result::text)>8000000 then raise exception using errcode='22023',message='History is too large; choose a shorter range';end if;
 return result;
end $$;
revoke all on function household_private.balance_history(jsonb) from public,anon,authenticated;

create or replace function household_private.entry_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
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
end $$;






notify pgrst,'reload schema';
