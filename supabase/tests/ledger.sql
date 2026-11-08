begin;
create temporary table ledger_test_results(name text primary key,passed boolean);
do $$
declare actor uuid;sid uuid;source_account uuid;other_account uuid;foreign_account uuid;category uuid;property uuid;tx uuid;second_tx uuid;r jsonb;row_data jsonb;import_id uuid;
begin
 select owner_user_id into actor from household_private.settings where singleton;
 if actor is null then raise exception 'Run against an enrolled test owner';end if;
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency,source,external_id) values('Mock ledger Alpha','checking','CAD','monarch','mock-ledger-source') returning id into source_account;
 insert into household_private.accounts(name,kind,currency) values('Mock ledger Beta','checking','CAD') returning id into other_account;
 insert into household_private.accounts(name,kind,currency) values('Mock ledger USD','checking','USD') returning id into foreign_account;
 insert into household_private.categories(name) values('Mock ledger category '||gen_random_uuid()) returning id into category;
 insert into household_private.properties(name,kind) values('Mock parked property','rental') returning id into property;
 insert into household_private.transactions(account_id,category_id,property_id,date,description,amount_minor,fingerprint,source,external_id,source_data)
  values(source_account,category,property,'2026-10-01','Mock original shop',-125,'mock-original-fingerprint','monarch','mock-ledger-tx','{"tags":[{"name":"Mock renovation"}],"notes":"Mock unchanged source"}') returning id into tx;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint)
  values(source_account,'2026-10-02','Mock salary',2000,'mock-salary-fingerprint') returning id into second_tx;
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',1,'description_override','Mock edited shop','account_override_id',other_account));
 if not exists(select 1 from household_private.transactions where id=tx and description='Mock original shop' and account_id=source_account and property_id=property and source_data->>'notes'='Mock unchanged source' and fingerprint='mock-original-fingerprint') then raise exception 'Override changed original fields';end if;
 r:=public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',other_account,'description','edited','tags','renovation','min_minor',-200,'max_minor',0,'date_from','2026-10-01','date_to','2026-10-01'));
 if r->>'total'<>'1' or r->'rows'->0->>'description'<>'Mock edited shop' or r->'rows'->0->>'original_description'<>'Mock original shop' then raise exception 'Effective filters/override read failed';end if;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',1,'description_override','Stale edit'));raise exception 'Stale revision accepted';exception when serialization_failure then null;end;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',2,'account_override_id',foreign_account));raise exception 'Currency-changing account accepted';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',2,'description_override',' '));raise exception 'Blank override accepted';exception when invalid_parameter_value then null;end;
 insert into ledger_test_results values('overrides preserve source/property; effective filters; revision and currency checks',true);
 import_id:=household_private.monarch_stage(jsonb_build_object('account',jsonb_build_object('external_id','mock-ledger-source','name','Mock ledger Alpha','kind','checking','currency','CAD'),'period_start','2026-10-01','period_end','2026-10-31','expected_count',1,'transactions',jsonb_build_array(jsonb_build_object('external_id','mock-ledger-tx','account_external_id','mock-ledger-source','pending',false,'date','2026-10-01','description','Mock original shop','amount_minor',-125,'category','Mock','source_data','{}'::jsonb))),actor,'assistant');
 r:=household_private.monarch_commit(import_id,actor);
 if r->>'inserted'<>'0' or r->>'skipped'<>'1' then raise exception 'Override broke source reimport';end if;
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',2,'description_override',null,'account_override_id',null,'category_id',null));
 r:=public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',source_account,'sort','amount','direction','asc','limit',1));
 if r->>'total'<>'2' or r->'rows'->0->>'id'<>tx::text or r->'rows'->0->>'description'<>'Mock original shop' then raise exception 'Reset or amount ordering failed';end if;
 r:=public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',source_account,'sort','date','direction','asc','offset',1,'limit',1));
 if r->'rows'->0->>'id'<>second_tx::text then raise exception 'Stable pagination failed';end if;
 r:=public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',source_account,'description','salary','category_id','__unassigned'));
 if r->>'total'<>'1' then raise exception 'Unassigned or text filter failed';end if;
 begin perform public.household_v1('list_ledger_transactions','{"sort":"drop table","direction":"asc"}');raise exception 'Invalid sort accepted';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('list_ledger_transactions','{"min_minor":10,"max_minor":-10}');raise exception 'Reversed range accepted';exception when invalid_parameter_value then null;end;
 insert into ledger_test_results values('reset, source reimport deduplication, sorting, pagination and column filters',true);
 -- The new read/write endpoints retain the passkey gate.
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'otp',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 begin perform public.household_v1('list_ledger_transactions');raise exception 'OTP read ledger';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',3));raise exception 'OTP edited ledger';exception when insufficient_privilege then null;end;
 if has_function_privilege('authenticated','household_private.ledger_update(jsonb)','EXECUTE') or has_function_privilege('anon','household_private.ledger_query(jsonb)','EXECUTE') then raise exception 'Private helper exposed';end if;
 insert into ledger_test_results values('new ledger read/write methods require approved passkey access',true);
end $$;
select * from ledger_test_results order by name;
rollback;
