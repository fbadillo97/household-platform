-- All mock fixtures rolled back, including test sessions and source snapshots.
begin;
create temporary table source_test_results(name text primary key,passed boolean);
do $$
declare actor uuid;sid uuid;payload jsonb;ident uuid;ident2 uuid;result jsonb;bad jsonb;count_before integer;fp_kind text;
begin
 select owner_user_id into actor from household_private.settings where singleton;
 if actor is null then
  actor:=gen_random_uuid();insert into auth.users(id,email,email_confirmed_at,is_anonymous) values(actor,'mock-import-owner@example.invalid',now(),false);
  insert into household_private.memberships(user_id,status,role) values(actor,'approved','owner');
 end if;
 payload:='{"account":{"external_id":"mock-account","name":"Mock source account","kind":"checking","currency":"CAD"},"period_start":"2026-10-01","period_end":"2026-10-31","expected_count":2,"coverage_notes":["Mock excluded institution"],"transactions":[{"external_id":"mock-tx-1","account_external_id":"mock-account","pending":false,"date":"2026-10-01","description":"Mock shop","amount_minor":-125,"category":"Mock source groceries","source_data":{"notes":"Mock note","tags":[{"id":"mock-tag","name":"Mock tag"}],"category_type":"expense"}},{"external_id":"mock-tx-2","account_external_id":"mock-account","pending":false,"date":"2026-10-02","description":"Mock income","amount_minor":2000,"category":"Mock source salary","source_data":{"category_type":"income"}}]}';
 ident:=household_private.monarch_stage(payload,actor,'assistant');
 if exists(select 1 from household_private.transactions where source='monarch' and external_id like 'mock-tx-%') then raise exception 'Staging wrote transactions';end if;
 if ident<>household_private.monarch_stage(payload,actor,'assistant') then raise exception 'Same snapshot not idempotent';end if;
 result:=household_private.monarch_commit(ident,actor);
 if (result->>'inserted')::integer<>2 then raise exception 'Wrong imported count';end if;
 if (select sum(amount_minor) from household_private.transactions where source='monarch' and external_id like 'mock-tx-%')<>1875 then raise exception 'Amounts changed';end if;
 if (select source_data->>'notes' from household_private.transactions where source='monarch' and external_id='mock-tx-1')<>'Mock note' then raise exception 'Metadata lost';end if;
 if (select notes from household_private.transactions where external_id='mock-tx-1')<>'Mock note' then raise exception 'Source notes not hydrated';end if;
 update household_private.transactions set notes='Local note',tags_override=array['Local tag'] where external_id='mock-tx-1';
 if household_private.monarch_commit(ident,actor)->>'inserted'<>'0' then raise exception 'Replay inserted duplicates';end if;
 -- A different snapshot containing existing IDs is also safe to import again.
 ident2:=household_private.monarch_stage(payload||'{"coverage_notes":["Different mock coverage note"]}'::jsonb,actor,'assistant');
 result:=household_private.monarch_commit(ident2,actor);
 if result->>'inserted'<>'0' or result->>'skipped'<>'2' then raise exception 'External ID dedup failed';end if;
 if (select notes from household_private.transactions where external_id='mock-tx-1')<>'Local note' or (select tags_override from household_private.transactions where external_id='mock-tx-1')<>array['Local tag'] then raise exception 'Replay replaced local edits';end if;
 insert into source_test_results values('stage/commit counts, cents, metadata, replay and cross-snapshot deduplication',true);
 bad:=jsonb_set(payload,'{transactions,0,account_external_id}','"wrong-account"');
 begin perform household_private.monarch_stage(bad,actor,'assistant');raise exception 'Cross-account row accepted';exception when invalid_parameter_value then null;end;
 bad:=jsonb_set(payload,'{transactions,0,pending}','true');
 begin perform household_private.monarch_stage(bad,actor,'assistant');raise exception 'Pending row accepted';exception when invalid_parameter_value then null;end;
 bad:=jsonb_set(payload,'{expected_count}','3');
 begin perform household_private.monarch_stage(bad,actor,'assistant');raise exception 'Count mismatch accepted';exception when invalid_parameter_value then null;end;
 bad:=jsonb_set(payload,'{transactions,0,amount_minor}','-1.25');
 begin perform household_private.monarch_stage(bad,actor,'assistant');raise exception 'Fractional cents accepted';exception when invalid_parameter_value then null;end;
 bad:=jsonb_set(payload,'{transactions,0,date}','"2026-11-01"');
 begin perform household_private.monarch_stage(bad,actor,'assistant');raise exception 'Out-of-period row accepted';exception when invalid_parameter_value then null;end;
 insert into source_test_results values('account, period, posted status, count and integer-cents validation',true);
 bad:=jsonb_set(payload,'{transactions,0,amount_minor}','-126');
 ident2:=household_private.monarch_stage(bad,actor,'assistant');
 begin perform household_private.monarch_commit(ident2,actor);raise exception 'Changed transaction silently overwritten';exception when serialization_failure then null;end;
 if (select amount_minor from household_private.transactions where source='monarch' and external_id='mock-tx-1')<>-125 then raise exception 'Failed import changed existing records';end if;
 if (select committed_at from household_private.source_snapshots where id=ident2) is not null then raise exception 'Failed commit finalized batch';end if;
 insert into source_test_results values('changed source transaction blocked and commit rolled back',true);
 -- The importer accepts all supported account kinds without inventing balances.
 foreach fp_kind in array array['loan','investment','asset'] loop
  bad:=jsonb_set(jsonb_set(payload,'{account,kind}',to_jsonb(fp_kind)),'{account,external_id}',to_jsonb('mock-'||fp_kind));
  bad:=jsonb_set(bad,'{transactions}',jsonb_build_array(jsonb_build_object('external_id','mock-kind-'||fp_kind,'account_external_id','mock-'||fp_kind,'pending',false,'date','2026-10-03','description','Mock kind','amount_minor',1,'source_data','{}'::jsonb)));
  bad:=jsonb_set(bad,'{expected_count}','1');
  perform household_private.monarch_commit(household_private.monarch_stage(bad,actor,'assistant'),actor);
  if not exists(select 1 from household_private.accounts where external_id='mock-'||fp_kind and kind=fp_kind) then raise exception 'Account kind lost';end if;
 end loop;
 if has_table_privilege('authenticated','household_private.monarch_catalog_snapshots','SELECT') or has_table_privilege('anon','household_private.monarch_catalog_snapshots','INSERT') or not (select relrowsecurity from pg_class where oid='household_private.monarch_catalog_snapshots'::regclass) then raise exception 'Source catalogs exposed';end if;
 insert into source_test_results values('broader account kinds, insert-only notes and private catalogs',true);
 -- Browser entry still requires a passkey; internal helpers cannot be executed by browser roles.
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'otp',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 begin perform public.household_v1('list_source_snapshots');raise exception 'OTP read source snapshots';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('stage_monarch_snapshot',payload);raise exception 'OTP staged source snapshot';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('commit_monarch_snapshot',jsonb_build_object('id',ident));raise exception 'OTP committed source snapshot';exception when insufficient_privilege then null;end;
 if has_function_privilege('authenticated','household_private.monarch_stage(jsonb,uuid,text)','EXECUTE') or has_function_privilege('anon','household_private.monarch_commit(uuid,uuid)','EXECUTE') or has_table_privilege('authenticated','household_private.source_snapshots','SELECT') then raise exception 'Private helper/table privileges exposed';end if;
 insert into source_test_results values('passkey gate, private tables and helper privileges remain enforced',true);
end $$;
select * from source_test_results order by name;
rollback;
