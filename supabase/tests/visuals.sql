-- Administrative, rollback-only test with fabricated identity and presentation data.
begin;
create temporary table visual_test_results(name text,passed boolean);
do $$
declare actor uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();account uuid;cat uuid;payee uuid;brand text:='mock-'||actor;result jsonb;snapshot jsonb;revision integer;isolated_owner boolean;
begin
 select not exists(select 1 from household_private.memberships where role='owner') into isolated_owner;
 insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at,updated_at) values(actor,'mock-visual-'||actor||'@example.invalid',now(),false,now(),now());insert into household_private.memberships(user_id,status,role) values(actor,'approved',case when isolated_owner then 'owner' else 'member' end);insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency) values('Mock visual account '||actor,'checking','XVS') returning id into account;insert into household_private.categories(name) values('Mock visual category '||actor) returning id into cat;insert into household_private.payees(name,kind) values('Mock visual payee '||actor,'business') returning id into payee;
 select to_jsonb(a) into snapshot from household_private.accounts a where id=account;
 if isolated_owner then
 result:=public.household_visuals_v1('visuals_save_brand',jsonb_build_object('key',brand,'name','Mock official logo','aliases',jsonb_build_array('Mock brand'),'png_base64','iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=','source_url','https://example.invalid/logo.png','revision',0));
 if result->>'revision'<>'1' then raise exception 'Brand was not saved';end if;
 result:=public.household_visuals_v1('visuals_save_brand',jsonb_build_object('key',brand,'name','Mock official logo updated','aliases',jsonb_build_array('Mock brand updated'),'png_base64',null,'source_url','https://example.invalid/logo-new.png','revision',1));
 if result->>'revision'<>'2' then raise exception 'Brand update lost revision';end if;
 begin perform public.household_visuals_v1('visuals_save_brand',jsonb_build_object('key',brand,'name','Mock','aliases','[]'::jsonb,'png_base64',null,'source_url','https://example.invalid/logo.png','revision',1));raise exception 'Stale logo overwrite accepted';exception when serialization_failure then null;end;
 begin perform public.household_visuals_v1('visuals_save_brand',jsonb_build_object('key','invalid-mock','name','Mock','aliases','[]'::jsonb,'png_base64','PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+','source_url','https://example.invalid/logo.png','revision',0));raise exception 'SVG/HTML image accepted';exception when invalid_parameter_value then null;end;
 insert into visual_test_results values('isolated owner shared-logo save/update/clear, stale revisions and PNG-only API validation',true);
 else
 insert into household_private.visual_brands(key,name,aliases,png,source_url,revision) values(brand,'Mock official logo updated',array['Mock brand updated'],null,'https://example.invalid/logo-new.png',2);
 end if;
 if household_private.visual_png_valid(convert_to('<svg onload=alert(1)>','UTF8')) then raise exception 'Non-PNG image accepted';end if;
 result:=public.household_visuals_v1('visuals_save_preference',jsonb_build_object('entity_type','account','entity_id',account,'brand_mode','brand','brand_key',brand,'icon','wallet','tone','teal','revision',0));
 result:=public.household_visuals_v1('visuals_save_preference',jsonb_build_object('entity_type','category','entity_id',cat,'brand_mode','auto','brand_key',null,'icon','gift','tone','rose','revision',0));
 begin perform public.household_visuals_v1('visuals_save_preference',jsonb_build_object('entity_type','category','entity_id',cat,'brand_mode','auto','icon','house','tone','green','revision',0));raise exception 'Stale appearance overwritten';exception when serialization_failure then null;end;
 begin perform public.household_visuals_v1('visuals_save_preference',jsonb_build_object('entity_type','account','entity_id',gen_random_uuid(),'brand_mode','auto','revision',0));raise exception 'Unknown target accepted';exception when invalid_parameter_value then null;end;
 result:=public.household_visuals_v1('visuals_save_preference',jsonb_build_object('entity_type','account','entity_id',account,'brand_mode','auto','brand_key',null,'icon',null,'tone',null,'revision',1));
 if result->>'revision'<>'2' or (select to_jsonb(a) from household_private.accounts a where id=account)<>snapshot then raise exception 'Reset failed or financial record changed';end if;
 execute 'set local role authenticated';result:=public.household_visuals_v1('visuals_get_catalog','{}');execute 'reset role';
 if not exists(select 1 from jsonb_array_elements(result->'brands') b where b->>'key'=brand and b->>'name'='Mock official logo updated' and b->'png_base64'='null'::jsonb) then raise exception 'Shared catalog did not reflect logo update';end if;
 if has_table_privilege('authenticated','household_private.visual_brands','SELECT') or has_function_privilege('authenticated','household_private.visual_png_valid(bytea)','EXECUTE') or has_function_privilege('anon','public.household_visuals_v1(text,jsonb)','EXECUTE') then raise exception 'Visual database grants too broad';end if;
 update household_private.memberships set role='member' where user_id=actor;
 begin perform public.household_visuals_v1('visuals_save_brand','{}');raise exception 'Member replaced shared logo';exception when insufficient_privilege then null;end;
 result:=public.household_visuals_v1('visuals_save_preference',jsonb_build_object('entity_type','payee','entity_id',payee,'brand_mode','none','icon','receipt','tone','neutral','revision',0));
 update household_private.memberships set status='removed' where user_id=actor;
 begin perform public.household_visuals_v1('visuals_get_catalog','{}');raise exception 'Removed member read logos';exception when insufficient_privilege then null;end;
 update household_private.memberships set status='approved' where user_id=actor;delete from auth.mfa_amr_claims where session_id=sid;
 begin perform public.household_visuals_v1('visuals_get_catalog','{}');raise exception 'Non-passkey session read logos';exception when insufficient_privilege then null;end;
 insert into visual_test_results values('saved catalog propagation and PNG validation without changing an existing owner',true),('appearance overrides/reset leave financial records unchanged',true),('approved passkey-only catalog, owner logo writes and private table/helper grants',true);
end $$;
select * from visual_test_results order by name;
rollback;
