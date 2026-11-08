-- Category-driven movement classification. Keeps source records, explicit peers and audited revisions intact.
alter table household_private.categories
 add column accounting_behavior text not null default 'regular'
 check(accounting_behavior in ('regular','transfer','credit_card_payment'));
-- Conservative exact-name mapping only; never guess from generic names like "Payment".
update household_private.categories
 set accounting_behavior='credit_card_payment'
 where lower(btrim(name)) in ('credit card payment','credit card payments');
update household_private.categories
 set accounting_behavior='transfer'
 where lower(btrim(name)) in ('transfer','transfers','transfer between accounts','bank transfer');

create function household_private.apply_category_accounting() returns trigger
language plpgsql security definer set search_path='' as $$
declare behavior text; account_kind text;
begin
 if tg_op='INSERT' or (new.category_id is distinct from old.category_id)
  or (tg_op='UPDATE' and old.transfer_peer_id is not null and new.transfer_peer_id is null)
  or (tg_op='UPDATE' and old.category_id is not distinct from new.category_id and new.flow_type is distinct from old.flow_type and new.transfer_peer_id is null) then
  -- Explicit reciprocal links have priority over category defaults until unlinked.
  if new.transfer_peer_id is not null then return new;end if;
  select coalesce(c.accounting_behavior,'regular') into behavior
   from household_private.categories c where c.id=new.category_id;
  behavior:=coalesce(behavior,'regular');
  if behavior<>'regular' and new.amount_minor=0 then
   raise exception using errcode='22023',message='A zero-amount transaction cannot be a transfer';
  end if;
  if behavior='credit_card_payment' then
   select a.kind into account_kind from household_private.accounts a
    where a.id=coalesce(new.account_override_id,new.account_id);
   if not ((account_kind='credit' and new.amount_minor>0) or (account_kind<>'credit' and new.amount_minor<0)) then
    raise exception using errcode='22023',message='Card-payment category requires money leaving a funding account or arriving on a credit card';
   end if;
  end if;
  new.flow_type:=behavior;
 end if;
 return new;
end $$;
create trigger category_accounting_on_transaction
 before insert or update of category_id,transfer_peer_id,flow_type on household_private.transactions
 for each row execute function household_private.apply_category_accounting();

-- Review existing unlinked entries; do not silently alter old imports or classified transactions here.
-- Category changes will apply the behavior atomically to each record when edited.
create function household_private.category_behavior_action(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id(); role text:=household_private.member_role();
 ident uuid; behavior text; revised jsonb;
begin
 if payload is null or jsonb_typeof(payload)<>'object'
 or (select count(*) from jsonb_object_keys(payload))<>2
 or not(payload?'id' and payload?'accounting_behavior') then
  raise exception using errcode='22023',message='Provide a category and accounting behavior';
 end if;
 ident:=(payload->>'id')::uuid;
 behavior:=payload->>'accounting_behavior';
 if behavior not in ('regular','transfer','credit_card_payment') then
  raise exception using errcode='22023',message='Invalid accounting behavior';
 end if;
 update household_private.categories set accounting_behavior=behavior where id=ident
 returning to_jsonb(categories.*) into revised;
 if revised is null then raise exception using errcode='P0002',message='Category not found';end if;
 -- Existing unlinked categorized entries inherit the updated category rule.
 -- Linked pairs retain their validated peer relationships.
 update household_private.transactions
 set flow_type=behavior, revision=revision+1
 where category_id=ident and deleted_at is null and transfer_peer_id is null
 and flow_type is distinct from behavior;
 insert into household_private.audit_events(actor_id,action,target_id)
 values(actor,'update_category_behavior',ident);
 return revised;
end $$;
revoke all on function household_private.apply_category_accounting(),household_private.category_behavior_action(jsonb) from public,anon,authenticated;
create or replace function household_private.entry_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
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
end $$;
notify pgrst,'reload schema';
