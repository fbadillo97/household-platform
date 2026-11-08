-- Administrative connection only. Mock transaction/session fixtures are rolled back.
begin;
create temporary table details_test_results(name text primary key,passed boolean);
do $$
declare actor uuid;sid uuid;account uuid;tx uuid;receipt jsonb;r jsonb;revision integer;path text;snapshot uuid;
begin
 select owner_user_id into actor from household_private.settings where singleton;
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency,source,external_id) values('Mock detail account','checking','CAD','monarch','mock-detail-account') returning id into account;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,source,external_id,source_data)
  values(account,'2026-10-01','Mock detail purchase',-125,'mock-detail-hash','monarch','mock-detail-tx','{"tags":[{"name":"Imported mock tag"}]}') returning id into tx;
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',1,'notes','Mock note with <escaped> content','review_status','reviewed','needs_attention',true,'tags_override',jsonb_build_array('Local mock tag')));
 r:=public.household_v1('get_transaction_detail',jsonb_build_object('id',tx));
 if r->>'notes'<>'Mock note with <escaped> content' or r->>'review_status'<>'reviewed' or r->>'needs_attention'<>'true' or r->'original_tags'->>0<>'Imported mock tag' then raise exception 'Detail save lost fields';end if;
 if r->>'reviewed_at' is null or r->'source_data'->'tags'->0->>'name'<>'Imported mock tag' then raise exception 'Review timestamp or source preservation failed';end if;
 r:=public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',account,'query','escaped','tags','Local','review','needs_attention'));
 if r->>'total'<>'1' then raise exception 'Notes/review/local-tag search failed';end if;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',2,'notes',repeat('x',10001)));raise exception 'Oversized note accepted';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',2,'tags_override',jsonb_build_array('repeat','REPEAT')));raise exception 'Repeated tags accepted';exception when invalid_parameter_value then null;end;
 receipt:=public.household_v1('prepare_receipt',jsonb_build_object('transaction_id',tx,'filename','mock.pdf','mime_type','application/pdf','byte_size',12,'sha256',repeat('a',64)));
 path:=receipt->>'object_path';
 if not household_private.receipt_permission(path,'upload') or household_private.receipt_permission('unknown/path','read') then raise exception 'Prepared path boundary failed';end if;
 begin perform public.household_v1('finish_receipt_upload',jsonb_build_object('id',receipt->>'id','revision',1));raise exception 'Missing object finalized';exception when invalid_parameter_value then null;end;
 execute 'set local role authenticated';
 insert into storage.objects(bucket_id,name,metadata) values('household-receipts',path,'{"size":12,"mimetype":"application/pdf"}');
 if (select count(*) from storage.objects where bucket_id='household-receipts' and name=path)<>1 then raise exception 'Storage select policy blocked approved user';end if;
 begin insert into storage.objects(bucket_id,name) values('household-receipts','unprepared/path');raise exception 'Unprepared path allowed';exception when insufficient_privilege then null;end;
 execute 'reset role';
 receipt:=public.household_v1('finish_receipt_upload',jsonb_build_object('id',receipt->>'id','revision',1));
 if receipt->>'state'<>'ready' or not household_private.receipt_permission(path,'read') then raise exception 'Receipt finalization/read failed';end if;
 if (public.household_v1('prepare_receipt',jsonb_build_object('transaction_id',tx,'filename','mock.pdf','mime_type','application/pdf','byte_size',12,'sha256',repeat('a',64)))->>'already_exists')<>'true' then raise exception 'Receipt hash dedup failed';end if;
 insert into details_test_results values('notes/tags/review metadata, strict validation, prepared upload and duplicate receipt checks',true);
 r:=public.household_v1('trash_transaction',jsonb_build_object('id',tx,'revision',2));
 if r->>'deleted_at' is null or jsonb_array_length(r->'receipts')<>1 then raise exception 'Trash lost receipt';end if;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',account))->>'total'<>'0' then raise exception 'Trash visible in active ledger';end if;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',account,'trash_only',true))->>'total'<>'1' then raise exception 'Trash missing from recovery view';end if;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',3,'notes','Forbidden'));raise exception 'Trashed record edited';exception when serialization_failure then null;end;
 if household_private.receipt_permission(path,'upload') or household_private.receipt_permission(path,'remove') then raise exception 'Trash allowed receipt mutation';end if;
 -- Source identity survives trash; a repeat source snapshot cannot resurrect the record.
 snapshot:=household_private.monarch_stage(jsonb_build_object('account',jsonb_build_object('external_id','mock-detail-account','name','Mock detail account','kind','checking','currency','CAD'),'period_start','2026-10-01','period_end','2026-10-31','expected_count',1,'transactions',jsonb_build_array(jsonb_build_object('external_id','mock-detail-tx','account_external_id','mock-detail-account','pending',false,'date','2026-10-01','description','Mock detail purchase','amount_minor',-125,'source_data','{}'::jsonb))),actor,'assistant');
 r:=household_private.monarch_commit(snapshot,actor);
 if r->>'inserted'<>'0' or (select deleted_at is null from household_private.transactions where id=tx) then raise exception 'Reimport resurrected trash';end if;
 insert into details_test_results values('soft deletion hides records, retains receipts/source identity and blocks edits',true);
 r:=public.household_v1('restore_transaction',jsonb_build_object('id',tx,'revision',3));
 if r->>'deleted_at' is not null or r->>'notes'<>'Mock note with <escaped> content' or jsonb_array_length(r->'receipts')<>1 then raise exception 'Restore lost data';end if;
 begin perform public.household_v1('finish_receipt_removal',jsonb_build_object('id',receipt->>'id','revision',2));raise exception 'Metadata removed before blob';exception when serialization_failure then null;end;
 -- A cancelled pending upload has no blob to remove. Ready-object deletion is tested through the Storage API, never SQL.
 receipt:=public.household_v1('prepare_receipt',jsonb_build_object('transaction_id',tx,'filename','cancelled.pdf','mime_type','application/pdf','byte_size',12,'sha256',repeat('b',64)));
 path:=receipt->>'object_path';
 perform public.household_v1('finish_receipt_removal',jsonb_build_object('id',receipt->>'id','revision',1));
 if household_private.receipt_permission(path,'read') then raise exception 'Removed receipt readable';end if;
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'otp',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 begin perform public.household_v1('get_transaction_detail',jsonb_build_object('id',tx));raise exception 'OTP read detail';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('prepare_receipt',jsonb_build_object('transaction_id',tx));raise exception 'OTP prepared upload';exception when insufficient_privilege then null;end;
 execute 'set local role authenticated';
 if exists(select 1 from storage.objects where bucket_id='household-receipts') then raise exception 'OTP passed Storage RLS';end if;
 execute 'reset role';
 if household_private.receipt_permission(path,'read') or household_private.receipt_permission(path,'upload') then raise exception 'OTP storage access allowed';end if;
 if has_function_privilege('anon','household_private.receipt_permission(text,text)','EXECUTE') or has_table_privilege('authenticated','household_private.receipts','SELECT') or (select public from storage.buckets where id='household-receipts') then raise exception 'Public receipt privileges';end if;
 insert into details_test_results values('restore/removal lifecycle and passkey/private receipt boundaries',true);
end $$;
select * from details_test_results order by name;
rollback;
