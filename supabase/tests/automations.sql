-- Administrative verification; fabricated identities/records, always rolled back.
begin;
create temporary table automation_test_results(name text,passed boolean);
do $$
declare actor uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();a uuid;usd uuid;p uuid;cat uuid;movement uuid;r jsonb;rule_id uuid;alias_id uuid;tx uuid;tx2 uuid;tx3 uuid;event_id uuid;before_row jsonb;rev integer;scope_key text;
begin
 insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at,updated_at) values(actor,'mock-automation-'||actor||'@example.invalid',now(),false,now(),now());
 insert into household_private.memberships(user_id,status,role) values(actor,'approved','member');
 insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency) values('Mock automation bank '||actor,'checking','CAD') returning id into a;
 insert into household_private.accounts(name,kind,currency) values('Mock automation USD '||actor,'checking','USD') returning id into usd;
 insert into household_private.categories(name) values('Mock automation category '||actor) returning id into cat;
 insert into household_private.categories(name,accounting_behavior) values('Mock automation movement '||actor,'transfer') returning id into movement;
 r:=public.household_v1('create_payee',jsonb_build_object('name','Mock automation insurer '||actor,'aliases',jsonb_build_array('Mock insurer '||actor)));p:=(r->>'id')::uuid;
 select id into alias_id from household_private.payee_aliases where payee_id=p;
 -- Existing records are not retroactively changed by definitions or toggles.
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-01','Historical automation mock',-12500,'mock-auto-old-'||actor) returning id into tx;
 r:=public.household_v1('save_automation',jsonb_build_object('name','Mock insurance tag','conditions',jsonb_build_object('payee_id',p,'amount_min_minor',-12500,'amount_max_minor',-12500,'currency','CAD'),'actions',jsonb_build_object('add_tags',jsonb_build_array('Insurance'),'category_id',cat,'needs_attention',true),'enabled',true));rule_id:=(r->>'id')::uuid;scope_key:='rule:'||rule_id;
 if (select tags_override from household_private.transactions where id=tx) is not null then raise exception 'Historical record changed';end if;
 begin perform public.household_v1('save_automation',jsonb_build_object('name','Unsafe','conditions','{"description_contains":"x"}','actions','{"sql":"delete records"}'));raise exception 'Arbitrary action allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('save_automation',jsonb_build_object('name','No currency','conditions','{"amount_min_minor":100}','actions','{"needs_attention":true}'));raise exception 'Unscoped currency allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('save_automation',jsonb_build_object('name','Movement','conditions','{"description_contains":"x"}','actions',jsonb_build_object('category_id',movement)));raise exception 'Transfer category automated';exception when invalid_parameter_value then null;end;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,source,external_id,source_data)
 values(a,'2026-10-02','Mock insurer '||actor,-12500,'mock-auto-in-'||actor,'monarch','mock-auto-in-'||actor,'{"tags":["Home"],"notes":"Mock original"}') returning id into tx2;
 select to_jsonb(t) into before_row from household_private.transactions t where id=tx2;
 if before_row->>'payee_id' is distinct from p::text or before_row->>'category_id' is distinct from cat::text or before_row->'tags_override'<>'["Home","Insurance"]'::jsonb or before_row->>'needs_attention'<>'true' then raise exception 'Recognize then automate failed';end if;
 if before_row->>'description' is distinct from 'Mock insurer '||actor or before_row->>'amount_minor'<>'-12500' or before_row->>'flow_type'<>'regular' or before_row->'source_data'<>'{"tags":["Home"],"notes":"Mock original"}'::jsonb then raise exception 'Source/accounting changed';end if;
 select id into event_id from household_private.automation_events where transaction_id=tx2 and source_key=scope_key and status='applied';
 if event_id is null then raise exception 'Run result missing';end if;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('automation_source',scope_key))->>'total'<>'1' then raise exception 'Affected source filter failed';end if;
 if public.household_v1('automation_history',jsonb_build_object('source_key',scope_key))->'rows'->0->>'can_undo'<>'true' then raise exception 'Guarded undo missing';end if;
 perform public.household_v1('undo_automation',jsonb_build_object('id',event_id,'transaction_revision',(before_row->>'revision')::integer));
 if (select category_id is not null or tags_override is not null or needs_attention from household_private.transactions where id=tx2) then raise exception 'Undo failed to restore metadata';end if;
 if (select payee_id from household_private.transactions where id=tx2) is distinct from p then raise exception 'Undo removed earlier recognition';end if;
 begin perform public.household_v1('undo_automation',jsonb_build_object('id',event_id,'transaction_revision',3));raise exception 'Double undo allowed';exception when serialization_failure then null;end;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-03','Mock insurer '||actor,-12500,'mock-auto-again-'||actor) returning id into tx3;
 select id,after_revision into event_id,rev from household_private.automation_events where transaction_id=tx3 and source_key=scope_key;
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx3,'revision',rev,'notes','Mock later edit'));
 begin perform public.household_v1('undo_automation',jsonb_build_object('id',event_id,'transaction_revision',rev+1));raise exception 'Undo overwrote later edit';exception when serialization_failure then null;end;
 r:=public.household_v1('list_automations','{}');
 if not exists(select 1 from jsonb_array_elements(r->'rows') entry where entry->>'source_key'=scope_key and entry->>'applied_count'='2' and entry->>'kind'='rule') then raise exception 'Directory statistics/definition missing';end if;
 if not exists(select 1 from jsonb_array_elements(r->'rows') entry where entry->>'source_key'='alias:'||alias_id and entry->>'effective_enabled'='true') then raise exception 'Recognition rule missing from directory';end if;
 insert into automation_test_results values('validated definitions, alias-first matching, metadata-only execution, source filtering and revision-guarded Undo',true);
 -- Currency and amount are signed and exact. Disabling does not change past results.
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(usd,'2026-10-04','Mock insurer '||actor,-12500,'mock-auto-usd-'||actor) returning id into tx;
 if exists(select 1 from household_private.automation_events where transaction_id=tx and source_key=scope_key) then raise exception 'Cross-currency automation matched';end if;
 perform public.household_v1('toggle_automation',jsonb_build_object('kind','rule','id',rule_id,'revision',1,'enabled',false));
 begin perform public.household_v1('toggle_automation',jsonb_build_object('kind','rule','id',rule_id,'revision',1,'enabled',true));raise exception 'Stale toggle allowed';exception when serialization_failure then null;end;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-04','Mock insurer '||actor,-12500,'mock-auto-off-'||actor) returning id into tx;
 if exists(select 1 from household_private.automation_events where transaction_id=tx and source_key=scope_key) then raise exception 'Disabled rule ran';end if;
 perform public.household_v1('toggle_automation',jsonb_build_object('kind','alias','id',alias_id,'revision',1,'enabled',false));
 select revision into rev from household_private.payees where id=p;
 perform public.household_v1('update_payee',jsonb_build_object('id',p,'revision',rev,'name','Mock renamed insurer '||actor,'aliases',jsonb_build_array('Mock insurer '||actor)));
 if not exists(select 1 from household_private.payee_aliases where id=alias_id and not enabled) then raise exception 'Editing a payee lost the alias toggle/identity';end if;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-05','Mock insurer '||actor,-12500,'mock-alias-off-'||actor) returning id into tx;
 if (select payee_id from household_private.transactions where id=tx) is not null or public.household_v1('get_transaction_detail',jsonb_build_object('id',tx))->>'suggested_payee_id' is not null then raise exception 'Disabled recognition ran/suggested';end if;
 insert into automation_test_results values('signed currency isolation, future-only toggles, stale rejection and preserved payee alias switches',true);
 -- An invalidated action fails atomically, is visible, and does not reject the import.
 r:=public.household_v1('save_automation',jsonb_build_object('name','Mock failing action','conditions',jsonb_build_object('account_id',a,'description_contains','Mock failure '||actor),'actions',jsonb_build_object('payee_id',p,'add_tags',jsonb_build_array('Should not apply')),'enabled',true));
 select revision into rev from household_private.payees where id=p;
 perform public.household_v1('update_payee',jsonb_build_object('id',p,'revision',rev,'name','Mock archived insurer '||actor,'aliases',jsonb_build_array('Mock insurer '||actor),'archived',true));
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-06','Mock failure '||actor,-12500,'mock-failure-'||actor) returning id into tx;
 if not exists(select 1 from household_private.automation_events where transaction_id=tx and status='error') or (select tags_override is not null or payee_id is not null from household_private.transactions where id=tx) then raise exception 'Failure not visible/atomic';end if;
 -- Reimport deduplication never reruns rules or overwrites a manual correction.
 select count(*) into rev from household_private.automation_events where transaction_id=tx2;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,source,external_id) values(a,'2026-10-02','Mock changed reimport',-100,'mock-dedup-'||actor,'monarch','mock-auto-in-'||actor) on conflict(source,external_id) do nothing;
 if (select count(*) from household_private.automation_events where transaction_id=tx2)<>rev then raise exception 'Dedup replayed automation';end if;
 if has_function_privilege('authenticated','household_private.save_automation(jsonb,boolean)','EXECUTE') or has_table_privilege('authenticated','household_private.automations','SELECT') then raise exception 'Private automation access exposed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 begin perform public.household_v1('list_automations');raise exception 'Sessionless rules read';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('automation_history');raise exception 'Sessionless history read';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('save_automation','{}');raise exception 'Sessionless definition write';exception when insufficient_privilege then null;end;
 r:=household_private.save_automation(jsonb_build_object('name','Mock assistant draft','conditions',jsonb_build_object('account_id',a),'actions','{"needs_attention":true}'::jsonb),true);
 if r->>'enabled'<>'false' or r->>'updated_via'<>'assistant_admin' or r->>'updated_by' is not null then raise exception 'Administrative provenance/default-off failed';end if;
 insert into automation_test_results values('isolated errors, repeat-import safety, private grants and live-passkey authorization',true);
end $$;
select * from automation_test_results;
rollback;
