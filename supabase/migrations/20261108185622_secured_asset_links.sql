-- A debt-to-asset relationship allocates equity, never modifies balances.
alter table household_private.accounts add column secured_asset_id uuid references household_private.accounts(id);
create index accounts_secured_asset_idx on household_private.accounts(secured_asset_id);
alter table household_private.accounts add constraint accounts_secured_debt_check check(secured_asset_id is null or (kind in ('credit','loan','mortgage') and secured_asset_id<>id));
create table household_private.account_link_events(
 id uuid primary key default gen_random_uuid(),account_id uuid not null references household_private.accounts(id),
 previous_asset_id uuid references household_private.accounts(id),asset_id uuid references household_private.accounts(id),
 actor_id uuid,provenance text not null,created_at timestamptz not null default now()
);
create index account_link_events_account_idx on household_private.account_link_events(account_id);
create index account_link_events_previous_idx on household_private.account_link_events(previous_asset_id);
create index account_link_events_asset_idx on household_private.account_link_events(asset_id);
alter table household_private.account_link_events enable row level security;
revoke all on household_private.account_link_events from public,anon,authenticated;
create function household_private.validate_secured_asset() returns trigger
language plpgsql security definer set search_path='' as $$
declare target household_private.accounts;
begin
 if new.secured_asset_id is not null then
  select * into target from household_private.accounts where id=new.secured_asset_id for share;
  if target.id is null or target.kind in ('credit','loan','mortgage') or target.currency<>new.currency or target.id=new.id or new.kind not in ('credit','loan','mortgage') then
   raise exception using errcode='22023',message='Link a debt to a different non-debt asset in the same currency';end if;
 end if;
 if exists(select 1 from household_private.accounts d where d.secured_asset_id=new.id and (new.kind in ('credit','loan','mortgage') or d.currency<>new.currency)) then
  raise exception using errcode='22023',message='Unlink secured debts before changing this asset type or currency';end if;
 return new;
end $$;
create trigger validate_secured_asset before insert or update of secured_asset_id,kind,currency on household_private.accounts for each row execute function household_private.validate_secured_asset();
create function household_private.record_secured_asset() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if (tg_op='INSERT' and new.secured_asset_id is not null) or (tg_op='UPDATE' and new.secured_asset_id is distinct from old.secured_asset_id) then
  insert into household_private.account_link_events(account_id,previous_asset_id,asset_id,actor_id,provenance)
  values(new.id,case when tg_op='UPDATE' then old.secured_asset_id else null end,new.secured_asset_id,auth.uid(),case when auth.uid() is null then 'assistant_admin' else 'approved_member' end);
 end if;
 return null;
end $$;
create trigger record_secured_asset after insert or update of secured_asset_id on household_private.accounts for each row execute function household_private.record_secured_asset();
-- Private administrative entry for automatic linking during AI-assisted data entry.
-- The public dispatcher passes false; browser roles cannot execute this function.
create function household_private.set_account_security(payload jsonb,administrative boolean default false) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare a household_private.accounts;ident uuid;
begin
 if not administrative then perform household_private.member_role();end if;
 if jsonb_typeof(payload) is distinct from 'object' or not(payload?'secured_asset_id') or exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','revision','secured_asset_id')) then raise exception using errcode='22023',message='Provide an account, revision and secured asset';end if;
 ident:=(payload->>'id')::uuid;select * into a from household_private.accounts where id=ident for update;
 if a.id is null or a.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Account changed; reload before linking';end if;
 update household_private.accounts set secured_asset_id=(payload->>'secured_asset_id')::uuid,revision=revision+1 where id=ident returning * into a;
 return to_jsonb(a);
end $$;
revoke all on function household_private.validate_secured_asset(),household_private.record_secured_asset(),household_private.set_account_security(jsonb,boolean) from public,anon,authenticated;

create or replace function household_private.account_action(operation text,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();a household_private.accounts;ident uuid;
 day date;minor bigint;included boolean;account_name text;
begin
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>6000 then raise exception using errcode='22023',message='Invalid account request';end if;
 if operation not in ('create_account','update_account','archive_account','restore_account','save_account_balance') then raise exception using errcode='22023',message='Unknown account operation';end if;
 if operation='create_account' then
  if exists(select 1 from jsonb_object_keys(payload) k where k not in ('name','kind','currency','include_in_net_worth','secured_asset_id')) then raise exception using errcode='22023',message='Unsupported account field';end if;
  if jsonb_typeof(payload->'name') is distinct from 'string' or length(btrim(payload->>'name')) not between 1 and 120
   or coalesce(payload->>'kind','') not in ('checking','savings','credit','mortgage','loan','investment','asset','other')
   or coalesce(payload->>'currency','CAD') !~ '^[A-Z]{3}$' then raise exception using errcode='22023',message='Check the account name, type and three-letter currency';end if;
  if payload?'include_in_net_worth' and jsonb_typeof(payload->'include_in_net_worth')<>'boolean' then raise exception using errcode='22023',message='Invalid net worth inclusion';end if;
  insert into household_private.accounts(name,kind,currency,include_in_net_worth,secured_asset_id) values(btrim(payload->>'name'),payload->>'kind',coalesce(payload->>'currency','CAD'),coalesce((payload->>'include_in_net_worth')::boolean,true),(payload->>'secured_asset_id')::uuid) returning id into ident;
 else
  ident:=(payload->>'id')::uuid;
  select * into a from household_private.accounts where id=ident for update;
  if a.id is null then raise exception using errcode='P0002',message='Account not found';end if;
  if a.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Account changed; reload before saving';end if;
  if operation='update_account' then
   if exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','revision','name','include_in_net_worth','secured_asset_id')) then raise exception using errcode='22023',message='Account type and currency cannot be changed';end if;
   account_name:=case when payload?'name' then btrim(payload->>'name') else a.name end;
   if account_name is null or length(account_name) not between 1 and 120 or (payload?'name' and jsonb_typeof(payload->'name')<>'string') then raise exception using errcode='22023',message='Use an account name containing 1–120 characters';end if;
   if payload?'include_in_net_worth' and jsonb_typeof(payload->'include_in_net_worth')<>'boolean' then raise exception using errcode='22023',message='Invalid net worth inclusion';end if;
   included:=case when payload?'include_in_net_worth' then (payload->>'include_in_net_worth')::boolean else a.include_in_net_worth end;
   update household_private.accounts set name=account_name,include_in_net_worth=included,secured_asset_id=case when payload?'secured_asset_id' then (payload->>'secured_asset_id')::uuid else secured_asset_id end,revision=revision+1 where id=ident;
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
create or replace function household_private.entry_v1(operation text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
 if operation='set_account_security' then return household_private.set_account_security(payload,false);end if;
 if operation='list_automations' then return household_private.list_automations(payload);end if;
 if operation='save_automation' then return household_private.save_automation(payload,false);end if;
 if operation='toggle_automation' then return household_private.toggle_automation(payload);end if;
 if operation='automation_history' then return household_private.automation_history(payload);end if;
 if operation='undo_automation' then return household_private.undo_automation(payload);end if;
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
notify pgrst,'reload schema';
