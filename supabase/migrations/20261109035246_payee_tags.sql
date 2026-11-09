-- Payee classification is independent of transaction tags and accounting.
create table household_private.payee_tags(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 60),
 revision integer not null default 1,archived_at timestamptz,created_at timestamptz not null default now()
);
create unique index payee_tags_name_key on household_private.payee_tags(household_private.payee_key(name));
create table household_private.payee_tag_links(
 payee_id uuid not null references household_private.payees(id),tag_id uuid not null references household_private.payee_tags(id),primary key(payee_id,tag_id)
);
create index payee_tag_links_tag_idx on household_private.payee_tag_links(tag_id);
alter table household_private.payee_tags enable row level security;
alter table household_private.payee_tag_links enable row level security;
revoke all on household_private.payee_tags,household_private.payee_tag_links from public,anon,authenticated;
create function household_private.payee_tag_action(operation text,p jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();role text:=household_private.member_role();ident uuid;result jsonb;t household_private.payee_tags;r jsonb;n integer;
begin
 if jsonb_typeof(p) is distinct from 'object' or octet_length(p::text)>30000 then raise exception using errcode='22023',message='Invalid payee tag request';end if;
 if operation='list_payee_tags' then
 if p<>'{}'::jsonb then raise exception using errcode='22023',message='Unsupported tag filter';end if;
 select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('payee_count',(select count(*) from household_private.payee_tag_links l where l.tag_id=t.id)) order by lower(t.name),t.id),'[]') into result from household_private.payee_tags t;return result;end if;
 if operation in ('create_payee_tag','update_payee_tag')then
 if exists(select 1 from jsonb_object_keys(p)k where k not in ('id','revision','name','archived'))or jsonb_typeof(p->'name') is distinct from 'string' or length(btrim(p->>'name'))not between 1 and 60 or (p?'archived' and jsonb_typeof(p->'archived')<>'boolean')then raise exception using errcode='22023',message='Use a tag name of 1–60 characters';end if;
 if operation='create_payee_tag'then
 if p?'id' or p?'revision' or (select count(*)from household_private.payee_tags)>=200 then raise exception using errcode='22023',message='Use up to 200 payee tags';end if;
 insert into household_private.payee_tags(name)values(btrim(p->>'name'))returning id into ident;
 else
 ident:=(p->>'id')::uuid;select * into t from household_private.payee_tags where id=ident for update;
 if t.id is null or t.revision is distinct from (p->>'revision')::integer then raise exception using errcode='40001',message='Tag changed; reload before saving';end if;
 update household_private.payee_tags set name=btrim(p->>'name'),revision=revision+1,archived_at=case when coalesce((p->>'archived')::boolean,t.archived_at is not null)then coalesce(t.archived_at,now())else null end where id=ident;end if;
 insert into household_private.audit_events(actor_id,action,target_id)values(actor,operation,ident);return jsonb_build_object('id',ident);
 end if;
 if operation<>'bulk_payee_tag' or exists(select 1 from jsonb_object_keys(p)k where k not in ('tag_id','action','payees'))or coalesce(p->>'action','')not in ('add','remove')or jsonb_typeof(p->'payees') is distinct from 'array' then raise exception using errcode='22023',message='Choose a tag, action and payees';end if;
 n:=jsonb_array_length(p->'payees');if n not between 1 and 100 or n<>(select count(distinct value->>'id')from jsonb_array_elements(p->'payees'))then raise exception using errcode='22023',message='Select 1–100 unique payees';end if;
 ident:=(p->>'tag_id')::uuid;select * into t from household_private.payee_tags where id=ident for share;
 if t.id is null or (p->>'action'='add' and t.archived_at is not null)then raise exception using errcode='22023',message='Choose an active payee tag';end if;
 perform a.id from household_private.payees a join jsonb_array_elements(p->'payees')v on a.id=(v->>'id')::uuid order by a.id for update of a;
 if n<>(select count(*)from household_private.payees a join jsonb_array_elements(p->'payees')v on a.id=(v->>'id')::uuid where a.revision=(v->>'revision')::integer and (p->>'action'='remove' or a.archived_at is null))then raise exception using errcode='40001',message='Payee changed; refresh and select again';end if;
 for r in select value from jsonb_array_elements(p->'payees')loop
 if p->>'action'='add'then
 if (select count(*)from household_private.payee_tag_links where payee_id=(r->>'id')::uuid)>=30 and not exists(select 1 from household_private.payee_tag_links where payee_id=(r->>'id')::uuid and tag_id=ident)then raise exception using errcode='22023',message='Use up to 30 tags per payee';end if;
 insert into household_private.payee_tag_links values((r->>'id')::uuid,ident)on conflict do nothing;
 else delete from household_private.payee_tag_links where payee_id=(r->>'id')::uuid and tag_id=ident;end if;
 update household_private.payees set revision=revision+1 where id=(r->>'id')::uuid;
 insert into household_private.audit_events(actor_id,action,target_id)values(actor,'payee_tag_'||(p->>'action'),(r->>'id')::uuid);
 end loop;return jsonb_build_object('updated',n);
exception when unique_violation then raise exception using errcode='22023',message='A payee tag with this name already exists';
end $$;
alter function household_private.payee_action(text,jsonb) rename to payee_action_before_tags;
create function household_private.payee_action(operation text,payload jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare role text:=household_private.member_role();actor uuid:=household_private.identity_id();result jsonb;ident uuid;tag uuid;tags jsonb:=payload->'tag_ids';
begin
 if payload?'tag_ids' then
 if operation not in ('create_payee','update_payee')or jsonb_typeof(tags) is distinct from 'array' or jsonb_array_length(tags)>30 or jsonb_array_length(tags)<>(select count(distinct value)from jsonb_array_elements_text(tags))then raise exception using errcode='22023',message='Choose up to 30 unique payee tags';end if;
 for tag in select value::uuid from jsonb_array_elements_text(tags)loop
 perform 1 from household_private.payee_tags t where t.id=tag and (t.archived_at is null or exists(select 1 from household_private.payee_tag_links l where l.tag_id=t.id and l.payee_id=nullif(payload->>'id','')::uuid))for share;
 if not found then raise exception using errcode='22023',message='Tag is unavailable; reload tags';end if;
 end loop;
 end if;
 result:=household_private.payee_action_before_tags(operation,payload-'tag_ids');ident:=(result->>'id')::uuid;
 if payload?'tag_ids'then
 delete from household_private.payee_tag_links where payee_id=ident and tag_id not in(select value::uuid from jsonb_array_elements_text(tags));
 insert into household_private.payee_tag_links select ident,value::uuid from jsonb_array_elements_text(tags)on conflict do nothing;
 insert into household_private.audit_events(actor_id,action,target_id)values(actor,'set_payee_tags',ident);end if;
 return result;
end $$;
create or replace function household_private.payee_list()returns jsonb language plpgsql security definer set search_path='' as $$
declare role text:=household_private.member_role();result jsonb;
begin
 if (select count(*)from household_private.payees)>2000 then raise exception using errcode='54000',message='Payee directory exceeds 2000 entries';end if;
 select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object(
 'aliases',coalesce((select jsonb_agg(a.description order by a.match_key)from household_private.payee_aliases a where a.payee_id=p.id),'[]'),
 'tags',coalesce((select jsonb_agg(to_jsonb(t)order by lower(t.name))from household_private.payee_tags t join household_private.payee_tag_links l on l.tag_id=t.id where l.payee_id=p.id),'[]'),
 'transaction_count',(select count(*)from household_private.transactions t where t.payee_id=p.id and t.deleted_at is null),
 'last_transaction',(select max(date)from household_private.transactions t where t.payee_id=p.id and t.deleted_at is null))order by lower(p.name),p.id),'[]')into result from household_private.payees p;return result;
end $$;
revoke all on function household_private.payee_tag_action(text,jsonb),household_private.payee_action(text,jsonb),household_private.payee_action_before_tags(text,jsonb),household_private.payee_list() from public,anon,authenticated;
CREATE OR REPLACE FUNCTION household_private.entry_v1(operation text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
 if operation in ('list_payee_tags','create_payee_tag','update_payee_tag','bulk_payee_tag') then return household_private.payee_tag_action(operation,payload);end if;
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
end $function$
;
notify pgrst,'reload schema';
