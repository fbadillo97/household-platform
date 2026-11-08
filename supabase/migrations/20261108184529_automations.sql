-- A bounded interpreter for metadata automations. No generated SQL or model calls.
alter table household_private.payee_aliases add column enabled boolean not null default true,
 add column revision integer not null default 1;
alter table household_private.transactions drop constraint transactions_payee_assignment_check;
alter table household_private.transactions add constraint transactions_payee_assignment_check check(payee_assignment in ('manual','alias','automation'));
create table household_private.automations(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 conditions jsonb not null,actions jsonb not null,enabled boolean not null default false,
 priority integer not null default 100 check(priority between 1 and 1000),revision integer not null default 1,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 updated_by uuid,updated_via text not null check(updated_via in ('approved_member','assistant_admin'))
);
create table household_private.automation_versions(
 id uuid primary key default gen_random_uuid(),source_key text not null,revision integer not null,
 definition jsonb not null,actor_id uuid,provenance text not null,created_at timestamptz not null default now()
);
create index automation_versions_source_idx on household_private.automation_versions(source_key,created_at desc);
create table household_private.automation_events(
 id uuid primary key default gen_random_uuid(),source_key text not null,
 transaction_id uuid not null references household_private.transactions(id),definition jsonb not null,
 status text not null check(status in ('applied','unchanged','error')),error_message text,
 before_values jsonb not null default '{}',after_values jsonb not null default '{}',after_revision integer,
 created_at timestamptz not null default clock_timestamp(),undone_at timestamptz,undone_by uuid
);
create index automation_events_source_idx on household_private.automation_events(source_key,created_at desc,id);
create index automation_events_transaction_idx on household_private.automation_events(transaction_id);
create index automation_events_recent_idx on household_private.automation_events(created_at desc,id);
alter table household_private.automations enable row level security;
alter table household_private.automation_versions enable row level security;
alter table household_private.automation_events enable row level security;
revoke all on household_private.automations,household_private.automation_versions,household_private.automation_events from public,anon,authenticated;

create function household_private.validate_automation(c jsonb,a jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare ident uuid;key text;v jsonb;
begin
 if c is null or a is null or jsonb_typeof(c)<>'object' or jsonb_typeof(a)<>'object' or c='{}' or a='{}' or octet_length(c::text||a::text)>8000 then
  raise exception using errcode='22023',message='Provide bounded conditions and actions';end if;
 if exists(select 1 from jsonb_object_keys(c) k where k not in ('payee_id','account_id','description_contains','amount_min_minor','amount_max_minor','currency'))
 or exists(select 1 from jsonb_object_keys(a) k where k not in ('payee_id','category_id','add_tags','review_status','needs_attention')) then
  raise exception using errcode='22023',message='Unsupported automation condition or action';end if;
 if c-'currency'='{}' then raise exception using errcode='22023',message='Choose a payee, account, description or amount condition';end if;
 foreach key in array array['payee_id','account_id'] loop
  if c?key then
   if jsonb_typeof(c->key)<>'string' then raise exception using errcode='22023',message='Condition IDs must be UUID strings';end if;
   ident:=(c->>key)::uuid;
   if key='payee_id' and not exists(select 1 from household_private.payees where id=ident and archived_at is null) then raise exception using errcode='22023',message='Choose an active condition payee';end if;
   if key='account_id' and not exists(select 1 from household_private.accounts where id=ident) then raise exception using errcode='22023',message='Choose an existing account';end if;
  end if;
 end loop;
 if c?'description_contains' and (jsonb_typeof(c->'description_contains')<>'string' or length(btrim(c->>'description_contains')) not between 1 and 200) then raise exception using errcode='22023',message='Use a description containing 1–200 characters';end if;
 if c?'currency' and (jsonb_typeof(c->'currency')<>'string' or c->>'currency' !~ '^[A-Z]{3}$') then raise exception using errcode='22023',message='Use a three-letter currency';end if;
 foreach key in array array['amount_min_minor','amount_max_minor'] loop
  if c?key then
   if jsonb_typeof(c->key)<>'number' or c->>key !~ '^-?[0-9]{1,12}$' or abs((c->>key)::numeric)>100000000000 or not c?'currency' then
    raise exception using errcode='22023',message='Amount conditions require signed integer cents and an explicit currency';end if;
  end if;
 end loop;
 if c?'amount_min_minor' and c?'amount_max_minor' and (c->>'amount_min_minor')::bigint>(c->>'amount_max_minor')::bigint then raise exception using errcode='22023',message='Minimum amount exceeds maximum';end if;
 if c?'account_id' and c?'currency' and not exists(select 1 from household_private.accounts where id=(c->>'account_id')::uuid and currency=c->>'currency') then raise exception using errcode='22023',message='Account and amount currencies differ';end if;
 foreach key in array array['payee_id','category_id'] loop
  if a?key and a->key<>'null'::jsonb then
   if jsonb_typeof(a->key)<>'string' then raise exception using errcode='22023',message='Action IDs must be UUID strings or null';end if;
   ident:=(a->>key)::uuid;
   if key='payee_id' and not exists(select 1 from household_private.payees where id=ident and archived_at is null) then raise exception using errcode='22023',message='Choose an active assignment payee';end if;
   if key='category_id' and not exists(select 1 from household_private.categories where id=ident and accounting_behavior='regular') then raise exception using errcode='22023',message='Automations can assign only normal income/expense categories';end if;
  end if;
 end loop;
 if a?'add_tags' then
  v:=a->'add_tags';
  if jsonb_typeof(v)<>'array' or jsonb_array_length(v) not between 1 and 5 then raise exception using errcode='22023',message='Add between 1 and 5 tags';end if;
  if exists(select 1 from jsonb_array_elements(v) tag where jsonb_typeof(tag)<>'string' or length(btrim(tag#>>'{}')) not between 1 and 60) then raise exception using errcode='22023',message='Use tag labels containing 1–60 characters';end if;
  if jsonb_array_length(v)<>(select count(distinct lower(btrim(tag))) from jsonb_array_elements_text(v) tag) then raise exception using errcode='22023',message='Use unique tags';end if;
 end if;
 if a?'needs_attention' and jsonb_typeof(a->'needs_attention')<>'boolean' then raise exception using errcode='22023',message='Attention action must be a boolean';end if;
 if a?'review_status' and (jsonb_typeof(a->'review_status')<>'string' or a->>'review_status' not in ('reviewed','unreviewed')) then raise exception using errcode='22023',message='Choose reviewed or unreviewed';end if;
end $$;
create function household_private.validate_automation_row() returns trigger
language plpgsql security definer set search_path='' as $$
begin perform household_private.validate_automation(new.conditions,new.actions);return new;end $$;
create trigger validate_automation_definition before insert or update of conditions,actions on household_private.automations
 for each row execute function household_private.validate_automation_row();

-- SECURITY INVOKER + revoked browser execution: administrative=true is available
-- only to an administrative connection, never as a client-supplied RPC option.
create function household_private.save_automation(payload jsonb,administrative boolean default false) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare actor uuid;via text;r household_private.automations;ident uuid;label text;prio integer;onoff boolean;
begin
 if not administrative then perform household_private.member_role();actor:=household_private.identity_id();end if;
 via:=case when administrative then 'assistant_admin' else 'approved_member' end;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>10000 or exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','revision','name','conditions','actions','priority','enabled')) then raise exception using errcode='22023',message='Invalid automation definition';end if;
 label:=btrim(payload->>'name');
 if jsonb_typeof(payload->'name') is distinct from 'string' or length(label) not between 1 and 120 then raise exception using errcode='22023',message='Use an automation name containing 1–120 characters';end if;
 perform household_private.validate_automation(payload->'conditions',payload->'actions');
 if payload?'enabled' and jsonb_typeof(payload->'enabled')<>'boolean' then raise exception using errcode='22023',message='Enabled must be a boolean';end if;
 prio:=coalesce((payload->>'priority')::integer,100);
 if prio not between 1 and 1000 then raise exception using errcode='22023',message='Priority must be 1–1000';end if;
 perform pg_advisory_xact_lock(hashtext('household_automation_definitions'));
 if payload?'id' then
  ident:=(payload->>'id')::uuid;select * into r from household_private.automations where id=ident for update;
  if r.id is null or r.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Automation changed; reload before revising';end if;
  onoff:=coalesce((payload->>'enabled')::boolean,r.enabled);
  update household_private.automations set name=label,conditions=payload->'conditions',actions=payload->'actions',enabled=onoff,priority=prio,revision=revision+1,updated_at=now(),updated_by=actor,updated_via=via where id=ident returning * into r;
 else
  if (select count(*) from household_private.automations)>=100 then raise exception using errcode='54000',message='Use up to 100 automations';end if;
  onoff:=coalesce((payload->>'enabled')::boolean,false);
  insert into household_private.automations(name,conditions,actions,enabled,priority,updated_by,updated_via) values(label,payload->'conditions',payload->'actions',onoff,prio,actor,via) returning * into r;
 end if;
 insert into household_private.automation_versions(source_key,revision,definition,actor_id,provenance) values('rule:'||r.id,r.revision,to_jsonb(r),actor,via);
 return to_jsonb(r);
end $$;

create function household_private.automation_matches(t household_private.transactions,c jsonb) returns boolean
language sql stable security definer set search_path='' as $$
 select (not c?'payee_id' or t.payee_id=(c->>'payee_id')::uuid)
 and (not c?'account_id' or coalesce(t.account_override_id,t.account_id)=(c->>'account_id')::uuid)
 and (not c?'description_contains' or strpos(lower(t.description),lower(btrim(c->>'description_contains')))>0)
 and (not c?'currency' or exists(select 1 from household_private.accounts a where a.id=coalesce(t.account_override_id,t.account_id) and a.currency=c->>'currency'))
 and (not c?'amount_min_minor' or t.amount_minor>=(c->>'amount_min_minor')::bigint)
 and (not c?'amount_max_minor' or t.amount_minor<=(c->>'amount_max_minor')::bigint);
$$;
create function household_private.automation_plan(t household_private.transactions,a jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare before_patch jsonb:='{}';after_patch jsonb:='{}';key text;tags text[];tag text;original_tags text[];
begin
 if a?'category_id' and (t.flow_type<>'regular' or t.transfer_peer_id is not null) then raise exception using errcode='22023',message='Category automation skipped: transfer accounting requires individual review';end if;
 foreach key in array array['payee_id','category_id','needs_attention','review_status'] loop
  if a?key and to_jsonb(t)->key is distinct from a->key then
   before_patch:=before_patch||jsonb_build_object(key,to_jsonb(t)->key);after_patch:=after_patch||jsonb_build_object(key,a->key);
   if key='payee_id' then before_patch:=before_patch||jsonb_build_object('payee_assignment',t.payee_assignment);after_patch:=after_patch||jsonb_build_object('payee_assignment','automation');end if;
   if key='review_status' then
    before_patch:=before_patch||jsonb_build_object('reviewed_at',t.reviewed_at,'reviewed_by',t.reviewed_by);
    after_patch:=after_patch||jsonb_build_object('reviewed_at',case when a->>'review_status'='reviewed' then now() else null end,'reviewed_by',null);
   end if;
  end if;
 end loop;
 if a?'add_tags' then
  select coalesce(array_agg(case when jsonb_typeof(v)='string' then v#>>'{}' else coalesce(v->>'name',v->>'id','') end),'{}'::text[]) into original_tags
   from jsonb_array_elements(case when t.tags_override is not null then to_jsonb(t.tags_override) when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) v;
  tags:=original_tags;
  for tag in select btrim(value) from jsonb_array_elements_text(a->'add_tags') loop
   if not exists(select 1 from unnest(tags) v where lower(v)=lower(tag)) then tags:=array_append(tags,tag);end if;
  end loop;
  if tags is distinct from original_tags then
   if cardinality(tags)>20 then raise exception using errcode='22023',message='Automation could not add tags: the transaction already has too many tags';end if;
   before_patch:=before_patch||jsonb_build_object('tags_override',t.tags_override);after_patch:=after_patch||jsonb_build_object('tags_override',tags);
  end if;
 end if;
 return jsonb_build_object('before',before_patch,'after',after_patch);
end $$;
create function household_private.automation_write(ident uuid,patch jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare revised integer;
begin
 if exists(select 1 from jsonb_object_keys(patch) k where k not in ('payee_id','payee_assignment','category_id','tags_override','review_status','reviewed_at','reviewed_by','needs_attention')) then raise exception using errcode='22023',message='Unsupported automation patch';end if;
 update household_private.transactions set
 payee_id=case when patch?'payee_id' then (patch->>'payee_id')::uuid else payee_id end,
 payee_assignment=case when patch?'payee_assignment' then patch->>'payee_assignment' else payee_assignment end,
 category_id=case when patch?'category_id' then (patch->>'category_id')::uuid else category_id end,
 tags_override=case when patch?'tags_override' then case when patch->'tags_override'='null'::jsonb then null else array(select jsonb_array_elements_text(patch->'tags_override')) end else tags_override end,
 review_status=case when patch?'review_status' then patch->>'review_status' else review_status end,
 reviewed_at=case when patch?'reviewed_at' then (patch->>'reviewed_at')::timestamptz else reviewed_at end,
 reviewed_by=case when patch?'reviewed_by' then (patch->>'reviewed_by')::uuid else reviewed_by end,
 needs_attention=case when patch?'needs_attention' then (patch->>'needs_attention')::boolean else needs_attention end,
 revision=revision+1 where id=ident returning revision into revised;
 return revised;
end $$;

create function household_private.run_import_automations() returns trigger
language plpgsql security definer set search_path='' as $$
declare r household_private.automations;current_row household_private.transactions;plan jsonb;revised integer;alias_record household_private.payee_aliases;definition jsonb;
begin
 -- BEFORE-import payee recognition runs first; conditions use this fixed snapshot.
 if new.payee_assignment='alias' and new.payee_id is not null then
  select * into alias_record from household_private.payee_aliases where payee_id=new.payee_id and match_key=household_private.payee_key(new.description) and enabled;
  if alias_record.id is not null then
   insert into household_private.automation_events(source_key,transaction_id,definition,status,before_values,after_values,after_revision)
   values('alias:'||alias_record.id,new.id,jsonb_build_object('kind','alias','description',alias_record.description,'payee_id',alias_record.payee_id,'revision',alias_record.revision),'applied',jsonb_build_object('payee_id',null,'payee_assignment',null),jsonb_build_object('payee_id',new.payee_id,'payee_assignment','alias'),new.revision);
  end if;
 end if;
 for r in select * from household_private.automations where enabled order by priority,created_at,id for share loop
  if household_private.automation_matches(new,r.conditions) then
   begin
    perform household_private.validate_automation(r.conditions,r.actions);
    select * into current_row from household_private.transactions where id=new.id;
    plan:=household_private.automation_plan(current_row,r.actions);revised:=current_row.revision;
    if plan->'after'<>'{}'::jsonb then revised:=household_private.automation_write(new.id,plan->'after');end if;
    insert into household_private.automation_events(source_key,transaction_id,definition,status,before_values,after_values,after_revision)
     values('rule:'||r.id,new.id,to_jsonb(r),case when plan->'after'='{}'::jsonb then 'unchanged' else 'applied' end,plan->'before',plan->'after',revised);
   exception when others then
    insert into household_private.automation_events(source_key,transaction_id,definition,status,error_message)
     values('rule:'||r.id,new.id,to_jsonb(r),'error',left(sqlerrm,1000));
   end;
  end if;
 end loop;
 return null;
end $$;
create trigger run_import_automations after insert on household_private.transactions for each row execute function household_private.run_import_automations();

create function household_private.automation_alias_audit() returns trigger
language plpgsql security definer set search_path='' as $$
declare d jsonb;key text;rev integer;
begin
 if tg_op='DELETE' then d:=to_jsonb(old)||jsonb_build_object('deleted',true);key:='alias:'||old.id;rev:=old.revision+1;
 else d:=to_jsonb(new);key:='alias:'||new.id;rev:=new.revision;end if;
 insert into household_private.automation_versions(source_key,revision,definition,actor_id,provenance)
 values(key,rev,d,auth.uid(),case when auth.uid() is null then 'assistant_admin' else 'approved_member' end);
 return null;
end $$;
create trigger automation_alias_audit after insert or update or delete on household_private.payee_aliases for each row execute function household_private.automation_alias_audit();

create function household_private.list_automations(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();off integer:=coalesce((payload->>'offset')::integer,0);result jsonb;
begin
 if off not between 0 and 100000 then raise exception using errcode='22023',message='Invalid automation page';end if;
 with sources as (
  select 'rule:'||r.id source_key,r.priority,r.created_at,to_jsonb(r)||jsonb_build_object('kind','rule','effective_enabled',r.enabled) definition from household_private.automations r
  union all
  select 'alias:'||a.id,0,p.created_at,to_jsonb(a)||jsonb_build_object('kind','alias','name',p.name,'effective_enabled',a.enabled and p.archived_at is null,'parent_archived',p.archived_at is not null) from household_private.payee_aliases a join household_private.payees p on p.id=a.payee_id
 ), page as (select * from sources order by priority,created_at,source_key limit 100 offset off)
 select jsonb_build_object('total',(select count(*) from sources),'offset',off,'limit',100,'rows',coalesce((select jsonb_agg(definition||jsonb_build_object('source_key',source_key,
  'applied_count',(select count(*) from household_private.automation_events e where e.source_key=page.source_key and e.status='applied'),
  'error_count',(select count(*) from household_private.automation_events e where e.source_key=page.source_key and e.status='error'),
  'last_event',(select jsonb_build_object('at',e.created_at,'status',e.status,'error',e.error_message) from household_private.automation_events e where e.source_key=page.source_key order by e.created_at desc,e.id desc limit 1)) order by priority,created_at,source_key) from page),'[]'::jsonb)) into result;
 return result;
end $$;
create function household_private.toggle_automation(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();ident uuid:=(payload->>'id')::uuid;r household_private.automations;a household_private.payee_aliases;p household_private.payees;
begin
 if jsonb_typeof(payload->'enabled') is distinct from 'boolean' or payload->>'kind' not in ('rule','alias') then raise exception using errcode='22023',message='Choose an automation and enabled state';end if;
 if payload->>'kind'='rule' then
  select * into r from household_private.automations where id=ident for update;
  if r.id is null or r.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Automation changed; refresh before toggling';end if;
  if (payload->>'enabled')::boolean then perform household_private.validate_automation(r.conditions,r.actions);end if;
  update household_private.automations set enabled=(payload->>'enabled')::boolean,revision=revision+1,updated_at=now(),updated_by=actor,updated_via='approved_member' where id=ident returning * into r;
  insert into household_private.automation_versions(source_key,revision,definition,actor_id,provenance) values('rule:'||ident,r.revision,to_jsonb(r),actor,'approved_member');
 else
  select * into a from household_private.payee_aliases where id=ident;
  select * into p from household_private.payees where id=a.payee_id for update;
  select * into a from household_private.payee_aliases where id=ident for update;
  if a.id is null or a.revision is distinct from (payload->>'revision')::integer then raise exception using errcode='40001',message='Recognition rule changed; refresh before toggling';end if;
  if p.archived_at is not null then raise exception using errcode='22023',message='Restore the payee before enabling recognition';end if;
  update household_private.payee_aliases set enabled=(payload->>'enabled')::boolean,revision=revision+1 where id=ident;
  update household_private.payees set revision=revision+1 where id=p.id;
 end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,'toggle_automation',ident);
 return jsonb_build_object('id',ident);
end $$;
create function household_private.automation_history(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();off integer:=coalesce((payload->>'offset')::integer,0);source text:=coalesce(payload->>'source_key','');result jsonb;
begin
 if off not between 0 and 100000 or length(source)>50 then raise exception using errcode='22023',message='Invalid automation activity page';end if;
 select jsonb_build_object('total',(select count(*) from household_private.automation_events e where source='' or e.source_key=source),'offset',off,'limit',50,'rows',coalesce((select jsonb_agg(data order by created_at desc,id desc) from (
  select e.created_at,e.id,to_jsonb(e)||jsonb_build_object('description',coalesce(t.description_override,t.description),'date',t.date,'transaction_revision',t.revision,'can_undo',e.status='applied' and e.undone_at is null and t.deleted_at is null and t.revision=e.after_revision) data
  from household_private.automation_events e join household_private.transactions t on t.id=e.transaction_id where source='' or e.source_key=source order by e.created_at desc,e.id desc limit 50 offset off
 ) entries),'[]'::jsonb)) into result;
 return result;
end $$;
create function household_private.undo_automation(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_role text:=household_private.member_role();e household_private.automation_events;t household_private.transactions;
begin
 select * into e from household_private.automation_events where id=(payload->>'id')::uuid for update;
 if e.id is null or e.status<>'applied' or e.undone_at is not null then raise exception using errcode='40001',message='This automation result cannot be undone';end if;
 select * into t from household_private.transactions where id=e.transaction_id for update;
 if t.deleted_at is not null or t.revision is distinct from e.after_revision or t.revision is distinct from (payload->>'transaction_revision')::integer then raise exception using errcode='40001',message='Transaction changed since this automation; review it individually';end if;
 if e.before_values?'category_id' and (t.flow_type<>'regular' or t.transfer_peer_id is not null or (e.before_values->>'category_id' is not null and not exists(select 1 from household_private.categories c where c.id=(e.before_values->>'category_id')::uuid and c.accounting_behavior='regular'))) then raise exception using errcode='40001',message='Accounting behavior changed; review the category individually';end if;
 perform household_private.automation_write(t.id,e.before_values);
 update household_private.automation_events set undone_at=now(),undone_by=actor where id=e.id;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,'undo_automation',e.transaction_id);
 return jsonb_build_object('id',e.transaction_id);
end $$;

create or replace function household_private.payee_action(operation text,payload jsonb) returns jsonb
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
 delete from household_private.payee_aliases where payee_id=ident and match_key not in (select household_private.payee_key(value) from jsonb_array_elements_text(aliases));
 insert into household_private.payee_aliases as current_alias(payee_id,description) select ident,btrim(value) from jsonb_array_elements_text(aliases)
 on conflict(match_key) do update set description=excluded.description,revision=current_alias.revision+1 where current_alias.payee_id=ident and current_alias.description is distinct from excluded.description;
 if (select count(*) from household_private.payee_aliases where payee_id=ident)<>jsonb_array_length(aliases) then raise exception using errcode='22023',message='An alias already belongs to another payee';end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);
 return jsonb_build_object('id',ident);
exception when unique_violation then
 raise exception using errcode='22023',message='Payee name or alias already exists; choose a unique name and description';
end $$;

create or replace function household_private.recognize_payee() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.payee_id is null and new.payee_assignment is null then
  select a.payee_id into new.payee_id from household_private.payee_aliases a
   join household_private.payees p on p.id=a.payee_id
   where a.match_key=household_private.payee_key(new.description) and p.archived_at is null and a.enabled;
  if new.payee_id is not null then new.payee_assignment:='alias';end if;
 end if;
 return new;
end $$;

create or replace function household_private.transaction_detail(payload jsonb)
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
    where a.match_key=household_private.payee_key(t.description) and p.archived_at is null and a.enabled) else null end,
  'original_description',t.description,'original_account_id',t.account_id,
  'original_tags',coalesce((select jsonb_agg(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end)
   from jsonb_array_elements(case when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) tag),'[]'::jsonb),
  'receipts',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from household_private.receipts r where r.transaction_id=t.id and r.removed_at is null),'[]'::jsonb)) into result
  from household_private.transactions t where t.id=(payload->>'id')::uuid;
 if result is null then raise exception using errcode='P0002',message='Transaction not found';end if;
 return result;
end $function$;

create or replace function household_private.entry_v1(operation text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=household_private.identity_id();result jsonb;actor_role text;ident uuid;
begin
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

create or replace function household_private.ledger_query(payload jsonb DEFAULT '{}'::jsonb)
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
   and (coalesce(payload->>'automation_source','')='' or exists(select 1 from household_private.automation_events ae where ae.transaction_id=e.id and ae.source_key=payload->>'automation_source' and ae.status='applied'))
   and (coalesce(payload->>'automation_event','')='' or exists(select 1 from household_private.automation_events ae where ae.transaction_id=e.id and ae.id=(payload->>'automation_event')::uuid))
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

revoke all on function household_private.validate_automation(jsonb,jsonb),household_private.validate_automation_row(),
 household_private.save_automation(jsonb,boolean),household_private.automation_matches(household_private.transactions,jsonb),
 household_private.automation_plan(household_private.transactions,jsonb),household_private.automation_write(uuid,jsonb),
 household_private.run_import_automations(),household_private.automation_alias_audit(),household_private.list_automations(jsonb),
 household_private.toggle_automation(jsonb),household_private.automation_history(jsonb),household_private.undo_automation(jsonb)
 from public,anon,authenticated;
notify pgrst,'reload schema';
