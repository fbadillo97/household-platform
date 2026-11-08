alter table household_private.accounts drop constraint accounts_kind_check;
alter table household_private.accounts add constraint accounts_kind_check check(kind in ('checking','savings','credit','mortgage','loan','investment','asset','other'));
alter table household_private.accounts add column revision integer not null default 1;
alter table household_private.accounts add column include_in_net_worth boolean not null default true;
alter table household_private.accounts add column archived_at timestamptz;
create table household_private.account_balance_snapshots(
 id uuid primary key default gen_random_uuid(),sequence bigint generated always as identity unique,
 account_id uuid not null references household_private.accounts(id),as_of date not null,
 amount_minor bigint not null check(amount_minor between -100000000000000 and 100000000000000),
 currency text not null check(currency ~ '^[A-Z]{3}$'),is_estimate boolean not null default false,
 note text not null default '' check(length(note)<=1000),created_at timestamptz not null default now(),
 created_by uuid not null references auth.users(id)
);
create index account_balances_latest_idx on household_private.account_balance_snapshots(account_id,as_of desc,sequence desc);
create index account_balances_creator_idx on household_private.account_balance_snapshots(created_by);
alter table household_private.account_balance_snapshots enable row level security;
revoke all on household_private.account_balance_snapshots from public,anon,authenticated;
revoke all on sequence household_private.account_balance_snapshots_sequence_seq from public,anon,authenticated;

create function household_private.account_list(ident uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();result jsonb;
begin
 select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('balance_snapshot',balance.value) order by a.name,a.id),'[]'::jsonb) into result
 from household_private.accounts a left join lateral(
  select jsonb_build_object('id',s.id,'as_of',s.as_of,'amount_minor',s.amount_minor,'currency',s.currency,'is_estimate',s.is_estimate,'note',s.note) value
  from household_private.account_balance_snapshots s where s.account_id=a.id order by s.as_of desc,s.sequence desc limit 1
 ) balance on true where ident is null or a.id=ident;
 return result;
end $$;
create function household_private.account_action(operation text,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();a household_private.accounts;ident uuid;
 day date;minor bigint;included boolean;account_name text;
begin
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>6000 then raise exception using errcode='22023',message='Invalid account request';end if;
 if operation not in ('create_account','update_account','archive_account','restore_account','save_account_balance') then raise exception using errcode='22023',message='Unknown account operation';end if;
 if operation='create_account' then
  if exists(select 1 from jsonb_object_keys(payload) k where k not in ('name','kind','currency','include_in_net_worth')) then raise exception using errcode='22023',message='Unsupported account field';end if;
  if jsonb_typeof(payload->'name') is distinct from 'string' or length(btrim(payload->>'name')) not between 1 and 120
   or coalesce(payload->>'kind','') not in ('checking','savings','credit','mortgage','loan','investment','asset','other')
   or coalesce(payload->>'currency','CAD') !~ '^[A-Z]{3}$' then raise exception using errcode='22023',message='Check the account name, type and three-letter currency';end if;
  if payload?'include_in_net_worth' and jsonb_typeof(payload->'include_in_net_worth')<>'boolean' then raise exception using errcode='22023',message='Invalid net worth inclusion';end if;
  insert into household_private.accounts(name,kind,currency,include_in_net_worth) values(btrim(payload->>'name'),payload->>'kind',coalesce(payload->>'currency','CAD'),coalesce((payload->>'include_in_net_worth')::boolean,true)) returning id into ident;
 else
  ident:=(payload->>'id')::uuid;
  select * into a from household_private.accounts where id=ident for update;
  if a.id is null then raise exception using errcode='P0002',message='Account not found';end if;
  if a.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Account changed; reload before saving';end if;
  if operation='update_account' then
   if exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','revision','name','include_in_net_worth')) then raise exception using errcode='22023',message='Account type and currency cannot be changed';end if;
   account_name:=case when payload?'name' then btrim(payload->>'name') else a.name end;
   if account_name is null or length(account_name) not between 1 and 120 or (payload?'name' and jsonb_typeof(payload->'name')<>'string') then raise exception using errcode='22023',message='Use an account name containing 1–120 characters';end if;
   if payload?'include_in_net_worth' and jsonb_typeof(payload->'include_in_net_worth')<>'boolean' then raise exception using errcode='22023',message='Invalid net worth inclusion';end if;
   included:=case when payload?'include_in_net_worth' then (payload->>'include_in_net_worth')::boolean else a.include_in_net_worth end;
   update household_private.accounts set name=account_name,include_in_net_worth=included,revision=revision+1 where id=ident;
  elsif operation in ('archive_account','restore_account') then
   if exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','revision')) then raise exception using errcode='22023',message='Unsupported archive field';end if;
   if (operation='archive_account' and a.archived_at is not null) or (operation='restore_account' and a.archived_at is null) then raise exception using errcode='40001',message='Account archive state changed; reload';end if;
   update household_private.accounts set archived_at=case when operation='archive_account' then now() else null end,revision=revision+1 where id=ident;
  else
   if a.archived_at is not null then raise exception using errcode='40001',message='Restore the account before updating its balance';end if;
   if exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','revision','amount_minor','as_of','note')) then raise exception using errcode='22023',message='Unsupported balance field';end if;
   if jsonb_typeof(payload->'amount_minor') is distinct from 'number' or coalesce(payload->>'amount_minor','') !~ '^-?[0-9]{1,15}$' then raise exception using errcode='22023',message='Use a balance in whole cents';end if;
   minor:=(payload->>'amount_minor')::bigint;
   if minor not between -100000000000000 and 100000000000000 or (a.kind in ('asset','other') and minor<0) then raise exception using errcode='22023',message='Balance is outside the supported range; estimated asset values cannot be negative';end if;
   if coalesce(payload->>'as_of','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception using errcode='22023',message='Use a valid as-of date';end if;
   begin day:=(payload->>'as_of')::date;exception when datetime_field_overflow or invalid_datetime_format then raise exception using errcode='22023',message='Use a valid as-of date';end;
   if day<'1900-01-01' or day>current_date then raise exception using errcode='22023',message='As-of date cannot be in the future or before 1900';end if;
   if payload?'note' and (jsonb_typeof(payload->'note') is distinct from 'string' or length(payload->>'note')>1000) then raise exception using errcode='22023',message='Use a note up to 1000 characters';end if;
   insert into household_private.account_balance_snapshots(account_id,as_of,amount_minor,currency,is_estimate,note,created_by)
    values(ident,day,minor,a.currency,a.kind in ('asset','other'),coalesce(payload->>'note',''),actor);
   update household_private.accounts set revision=revision+1 where id=ident;
  end if;
 end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);
 return household_private.account_list(ident)->0;
end $$;
revoke all on function household_private.account_list(uuid),household_private.account_action(text,jsonb) from public,anon,authenticated;

create or replace function household_private.entry_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
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
