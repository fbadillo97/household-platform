-- Run against the prepared project with an administrative SQL connection. Entire fixture is rolled back.
begin;
create temporary table verification_results(name text primary key, passed boolean not null);
grant select,insert on verification_results to authenticated,anon;
do $$
declare n text; actor uuid; sid uuid;
begin
 foreach n in array array['owner','member','other','unverified','anonymous'] loop
  actor:=gen_random_uuid();sid:=gen_random_uuid();
  perform set_config('test.'||n||'_id',actor::text,true);
  perform set_config('test.'||n||'_session',sid::text,true);
  insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at,updated_at)
   values(actor,'household-mock-'||n||'@example.invalid',case when n='unverified' then null else now() end,n='anonymous',now(),now());
  insert into auth.sessions(id,user_id,created_at,updated_at,aal) values(sid,actor,now(),now(),'aal1');
 end loop;
 update household_private.settings set owner_email='household-mock-owner@example.invalid',owner_user_id=null where singleton;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.member_id'),'session_id',current_setting('test.member_session'),'role','authenticated','user_metadata',jsonb_build_object('role','owner'))::text,true);
do $$
declare result jsonb;
begin
 result:=public.household_v1('request_access');
 if result->>'status'<>'pending' then raise exception 'New member bypassed pending state'; end if;
 begin perform public.household_v1('list_accounts');raise exception 'Pending data access allowed';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('create_account','{"name":"Forbidden","kind":"checking"}');raise exception 'Pending write allowed';exception when insufficient_privilege then null;end;
 begin perform * from household_private.accounts;raise exception 'Direct table access allowed';exception when insufficient_privilege then null;end;
 begin perform household_private.identity_id();raise exception 'Direct helper execution allowed';exception when insufficient_privilege then null;end;
 insert into verification_results values('pending denied; direct tables/helpers denied; metadata cannot escalate',true);
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.other_id'),'session_id',current_setting('test.other_session'),'role','authenticated')::text,true);
select public.household_v1('request_access');
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.owner_id'),'session_id',current_setting('test.owner_session'),'role','authenticated')::text,true);
do $$
declare result jsonb;
begin
 result:=public.household_v1('request_access');
 if result->>'status'<>'approved' or result->>'role'<>'owner' then raise exception 'Owner bootstrap failed';end if;
 perform public.household_v1('decide_access',jsonb_build_object('user_id',current_setting('test.member_id'),'status','approved','revision',1));
 perform public.household_v1('decide_access',jsonb_build_object('user_id',current_setting('test.other_id'),'status','rejected','revision',1));
 begin perform public.household_v1('decide_access',jsonb_build_object('user_id',current_setting('test.member_id'),'status','removed','revision',1));raise exception 'Stale approval accepted';exception when serialization_failure then null;end;
 begin perform public.household_v1('decide_access',jsonb_build_object('user_id',current_setting('test.owner_id'),'status','removed','revision',1));raise exception 'Owner removal accepted';exception when insufficient_privilege then null;end;
 if jsonb_array_length(public.household_v1('list_requests'))<>3 then raise exception 'Owner request list failed'; end if;
 insert into verification_results values('owner reserved-email bootstrap, decisions, revision and owner protections',true);
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.other_id'),'session_id',current_setting('test.other_session'),'role','authenticated')::text,true);
do $$begin
 if public.household_v1('request_access')->>'status'<>'rejected' then raise exception 'Rejected user reset request';end if;
 begin perform public.household_v1('list_accounts');raise exception 'Rejected data access allowed';exception when insufficient_privilege then null;end;
 insert into verification_results values('rejected account denied and cannot reset own decision',true);
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.member_id'),'session_id',current_setting('test.member_session'),'role','authenticated')::text,true);
do $$
declare account jsonb;prop jsonb;category jsonb;batch jsonb;second_batch jsonb;other_account jsonb;rows jsonb;result jsonb;transaction jsonb;first_row uuid;
begin
 begin perform public.household_v1('list_requests');raise exception 'Member read approval queue';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('decide_access',jsonb_build_object('user_id',current_setting('test.other_id'),'status','approved','revision',2));raise exception 'Member approved user';exception when insufficient_privilege then null;end;
 account:=public.household_v1('create_account','{"name":"Mock chequing","kind":"checking","currency":"CAD"}');
 prop:=public.household_v1('create_property','{"name":"Mock rental","kind":"rental"}');
 category:=public.household_v1('create_category','{"name":"Mock repair"}');
 rows:='[{"date":"2026-01-01","description":"Mock Coffee","amount":"-2.35"},{"date":"2026-01-01","description":" mock   coffee ","amount":"-2.35"},{"date":"2026-99-99","description":"Invalid","amount":"1"},{"date":"2026-01-01","description":"Invalid cents","amount":"1.001"}]';
 batch:=public.household_v1('stage_import',jsonb_build_object('account_id',account->>'id','rows',rows));
 if (batch->'rows'->0->>'duplicate')::boolean or not (batch->'rows'->1->>'duplicate')::boolean then raise exception 'Duplicate normalization failed';end if;
 if batch->'rows'->2->>'error' is null or batch->'rows'->3->>'error' is null then raise exception 'Invalid row accepted';end if;
 if jsonb_array_length(public.household_v1('list_transactions'))<>0 then raise exception 'Staging changed transactions';end if;
 begin perform public.household_v1('commit_import',jsonb_build_object('id',batch->>'id','row_ids',jsonb_build_array(batch->'rows'->0->>'id',batch->'rows'->2->>'id')));raise exception 'Invalid selection committed';exception when invalid_parameter_value then null;end;
 if jsonb_array_length(public.household_v1('list_transactions'))<>0 then raise exception 'Failed selection partially committed';end if;
 begin perform public.household_v1('commit_import',jsonb_build_object('id',batch->>'id','row_ids',jsonb_build_array(gen_random_uuid())));raise exception 'Foreign row selection committed';exception when invalid_parameter_value then null;end;
 second_batch:=public.household_v1('stage_import',jsonb_build_object('account_id',account->>'id','rows',jsonb_build_array(rows->0)));
 result:=public.household_v1('commit_import',jsonb_build_object('id',batch->>'id','row_ids',jsonb_build_array(batch->'rows'->0->>'id')));
 if (result->>'inserted')::integer<>1 then raise exception 'Commit count wrong';end if;
 begin perform public.household_v1('commit_import',jsonb_build_object('id',batch->>'id','row_ids',jsonb_build_array(batch->'rows'->0->>'id')));raise exception 'Replay allowed';exception when serialization_failure then null;end;
 begin perform public.household_v1('commit_import',jsonb_build_object('id',second_batch->>'id','row_ids',jsonb_build_array(second_batch->'rows'->0->>'id')));raise exception 'New duplicate skipped review';exception when serialization_failure then null;end;
 result:=public.household_v1('commit_import',jsonb_build_object('id',second_batch->>'id','row_ids',jsonb_build_array(second_batch->'rows'->0->>'id'),'duplicate_ids',jsonb_build_array(second_batch->'rows'->0->>'id')));
 other_account:=public.household_v1('create_account','{"name":"Other mock account","kind":"savings"}');
 result:=public.household_v1('stage_import',jsonb_build_object('account_id',other_account->>'id','rows',jsonb_build_array(rows->0)));
 if (result->'rows'->0->>'duplicate')::boolean then raise exception 'Duplicate crossed account boundary';end if;
 transaction:=public.household_v1('list_transactions')->0;
 if (transaction->>'amount_minor')::bigint<>-235 then raise exception 'Integer cents wrong';end if;
 perform public.household_v1('assign_transaction',jsonb_build_object('id',transaction->>'id','revision',1,'property_id',prop->>'id','category_id',category->>'id'));
 begin perform public.household_v1('assign_transaction',jsonb_build_object('id',transaction->>'id','revision',1));raise exception 'Stale assignment allowed';exception when serialization_failure then null;end;
 if jsonb_array_length(public.household_v1('list_transactions',jsonb_build_object('property_id',prop->>'id')))<>1 then raise exception 'Property filter failed';end if;
 perform set_config('test.batch_id',batch->>'id',true);
 insert into verification_results values('member isolation; normalized cents; staged validation; atomic commits; replay and duplicate review; filters and revisions',true);
end $$;
-- A different approved user still cannot commit another user's staged batch.
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.owner_id'),'session_id',current_setting('test.owner_session'),'role','authenticated')::text,true);
do $$begin
 begin perform public.household_v1('preview_import',jsonb_build_object('id',current_setting('test.batch_id')));raise exception 'Other user batch read allowed';exception when no_data_found then null;end;
 perform public.household_v1('decide_access',jsonb_build_object('user_id',current_setting('test.member_id'),'status','removed','revision',2));
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.member_id'),'session_id',current_setting('test.member_session'),'role','authenticated')::text,true);
do $$begin
 begin perform public.household_v1('list_accounts');raise exception 'Removed user retained access';exception when insufficient_privilege then null;end;
 insert into verification_results values('staging creator isolation and removal applies to existing JWT',true);
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.unverified_id'),'session_id',current_setting('test.unverified_session'),'role','authenticated')::text,true);
do $$begin
 begin perform public.household_v1('request_access');raise exception 'Unverified account accepted';exception when insufficient_privilege then null;end;
 insert into verification_results values('unverified email denied',true);
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.anonymous_id'),'session_id',current_setting('test.anonymous_session'),'role','authenticated')::text,true);
do $$begin
 begin perform public.household_v1('request_access');raise exception 'Anonymous authenticated role accepted';exception when insufficient_privilege then null;end;
 insert into verification_results values('anonymous Auth accounts denied despite authenticated role',true);
end $$;
-- Simulate a token whose referenced server-side session no longer exists.
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.owner_id'),'session_id',gen_random_uuid()::text,'role','authenticated')::text,true);
do $$begin
 begin perform public.household_v1('list_accounts');raise exception 'Revoked session accepted';exception when insufficient_privilege then null;end;
 insert into verification_results values('revoked session denied even for approved owner',true);
end $$;
set local role anon;
select set_config('request.jwt.claims','{}',true);
do $$begin
 begin perform public.household_v1('access_state');raise exception 'Signed-out RPC allowed';exception when insufficient_privilege then null;end;
 begin perform * from household_private.transactions;raise exception 'Signed-out table read allowed';exception when insufficient_privilege then null;end;
 insert into verification_results values('signed-out execution and direct records denied',true);
end $$;
select * from verification_results order by name;
rollback;
