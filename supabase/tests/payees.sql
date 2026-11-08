-- Administrative verification with fabricated records only; always rollback.
begin;
create temporary table payee_test_results(name text,passed boolean);
do $$
declare actor uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();otp_sid uuid;a uuid;p uuid;q uuid;tx uuid;imported uuid;r jsonb;before_row jsonb;rev integer;b1 uuid;b2 uuid;a2 uuid;
begin
 insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at,updated_at) values(actor,'mock-payee-'||actor||'@example.invalid',now(),false,now(),now());
 insert into household_private.memberships(user_id,status,role) values(actor,'approved','member');
 insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency) values('Mock payee bank '||actor,'checking','CAD') returning id into a;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,source,external_id,source_data) values(a,'2026-10-01','Mock shop '||actor,-1250,'mock-payee-'||actor,'monarch','mock-payee-'||actor,'{"notes":"Mock original","tags":["Mock"]}') returning id into tx;
 select to_jsonb(t) into before_row from household_private.transactions t where id=tx;
 r:=public.household_v1('create_payee',jsonb_build_object('name','Mock merchant '||actor,'kind','business','aliases',jsonb_build_array('Mock shop '||actor)));p:=(r->>'id')::uuid;
 if (select payee_id from household_private.transactions where id=tx) is not null then raise exception 'Existing records were backfilled';end if;
 if public.household_v1('get_transaction_detail',jsonb_build_object('id',tx))->>'suggested_payee_id'<>p::text then raise exception 'Exact alias suggestion missing';end if;
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',1,'payee_id',p));
 r:=public.household_v1('get_transaction_detail',jsonb_build_object('id',tx));
 if r->>'payee_id'<>p::text or r->>'payee_assignment'<>'manual' then raise exception 'Assignment missing';end if;
 if (select to_jsonb(t)-array['payee_id','payee_assignment','revision'] from household_private.transactions t where id=tx)<>(before_row-array['payee_id','payee_assignment','revision']) then raise exception 'Payee edit changed source/accounting/metadata';end if;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',1,'payee_id',null));raise exception 'Stale assignment accepted';exception when serialization_failure then null;end;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',a,'payee_id',p))->>'total'<>'1' then raise exception 'Payee filter missing';end if;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',a,'query','Mock merchant '||actor))->>'total'<>'1' then raise exception 'Payee search missing';end if;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',a,'sort','payee'))->'rows'->0->>'payee_name'<>'Mock merchant '||actor then raise exception 'Payee sorting/name missing';end if;
 insert into payee_test_results values('manual assignment, exact suggestion, stale edits, search/filter/sort and imported/accounting invariants',true);
 -- Future imports recognize case and whitespace variations, never prefixes or fuzzy substrings.
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-02','  MOCK   SHOP '||upper(actor::text)||'  ',1250,'mock-payee-auto-'||actor) returning id into imported;
 if (select payee_id is distinct from p or payee_assignment is distinct from 'alias' from household_private.transactions where id=imported) then raise exception 'Exact import recognition failed';end if;
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',imported,'revision',1,'payee_id',null));
 if public.household_v1('get_transaction_detail',jsonb_build_object('id',imported))->>'suggested_payee_id' is not null then raise exception 'Manual clear was re-suggested';end if;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',a,'payee_id','__unassigned'))->>'total'<>'1' then raise exception 'Unassigned filter failed';end if;
 r:=public.household_v1('create_payee',jsonb_build_object('name','Mock person '||actor,'kind','person'));q:=(r->>'id')::uuid;
 begin perform public.household_v1('update_payee',jsonb_build_object('id',q,'revision',1,'name','Mock person '||actor,'kind','person','aliases',jsonb_build_array('Mock shop '||actor)));raise exception 'Conflicting alias accepted';exception when invalid_parameter_value then null;end;
 if (select revision from household_private.payees where id=q)<>1 then raise exception 'Failed alias request partially applied';end if;
 begin perform public.household_v1('create_payee',jsonb_build_object('name','Mock duplicate '||actor,'aliases',jsonb_build_array('Mock x',' mock   X ')));raise exception 'Repeated aliases accepted';exception when invalid_parameter_value then null;end;
 perform public.household_v1('remember_payee_alias',jsonb_build_object('id',tx,'revision',2));
 begin perform public.household_v1('remember_payee_alias',jsonb_build_object('id',tx,'revision',1));raise exception 'Stale remember accepted';exception when serialization_failure then null;end;
 perform public.household_v1('update_payee',jsonb_build_object('id',p,'revision',1,'name','Mock renamed '||actor,'kind','institution','archived',true,'aliases',jsonb_build_array('Mock shop '||actor)));
 if (select payee_id from household_private.transactions where id=tx)<>p then raise exception 'Archive lost historical payee';end if;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',imported,'revision',2,'payee_id',p));raise exception 'Archived payee assigned';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('update_payee',jsonb_build_object('id',p,'revision',1,'name','stale'));raise exception 'Stale payee accepted';exception when serialization_failure then null;end;
 -- Bulk assignment is bounded, revision-checked and atomic.
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-03','Mock bulk one',-100,'mock-payee-b1-'||actor) returning id into b1;
 insert into household_private.accounts(name,kind,currency) values('Mock second payee bank '||actor,'savings','CAD') returning id into a2;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a2,'2026-10-03','Mock bulk two',100,'mock-payee-b2-'||actor) returning id into b2;
 r:=public.household_v1('bulk_update_transactions',jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',b1,'revision',1),jsonb_build_object('id',b2,'revision',1)),'action','payee','value',q));
 if r->>'updated_count'<>'2' then raise exception 'Bulk payee assignment failed';end if;
 begin perform public.household_v1('bulk_update_transactions',jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',b1,'revision',2),jsonb_build_object('id',b2,'revision',1)),'action','payee','value',null));raise exception 'Stale bulk accepted';exception when serialization_failure then null;end;
 if (select payee_id from household_private.transactions where id=b1) is distinct from q then raise exception 'Partial bulk completion';end if;
 perform public.household_v1('link_transfer',jsonb_build_object('id',b1,'revision',2,'peer_id',b2,'peer_revision',2,'flow_type','transfer'));
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',b1,'revision',3,'payee_id',null));
 if (select transfer_peer_id is distinct from b2 or flow_type is distinct from 'transfer' from household_private.transactions where id=b1) then raise exception 'Payee edit changed reciprocal transfer';end if;
 insert into payee_test_results values('future exact recognition, manual clearing, alias uniqueness/atomicity and recoverable archiving',true);
 -- The import pipeline's source-ID deduplication preserves the local payee on repeats.
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,source,external_id)
 values(a,'2026-10-01','Mock conflicting reimport',-9999,'mock-payee-repeat-'||actor,'monarch','mock-payee-'||actor)
 on conflict(source,external_id) do nothing;
 if (select payee_id from household_private.transactions where id=tx) is distinct from p or
 (select description from household_private.transactions where id=tx) is distinct from 'Mock shop '||actor then raise exception 'Reimport changed local assignment/source';end if;
 r:=public.household_v1('get_transaction_detail',jsonb_build_object('id',tx));
 perform public.household_v1('trash_transaction',jsonb_build_object('id',tx,'revision',(r->>'revision')::integer));
 r:=public.household_v1('get_transaction_detail',jsonb_build_object('id',tx));
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',(r->>'revision')::integer,'payee_id',null));raise exception 'Trash edited';exception when serialization_failure then null;end;
 perform public.household_v1('restore_transaction',jsonb_build_object('id',tx,'revision',(r->>'revision')::integer));
 if public.household_v1('get_transaction_detail',jsonb_build_object('id',tx))->>'payee_id'<>p::text then raise exception 'Trash/restore lost payee';end if;
 if has_table_privilege('authenticated','household_private.payees','SELECT') or has_table_privilege('anon','household_private.payee_aliases','SELECT') or has_function_privilege('authenticated','household_private.payee_action(text,jsonb)','EXECUTE') then raise exception 'Private payee access exposed';end if;
 otp_sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(otp_sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),otp_sid,'otp',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',otp_sid,'role','authenticated')::text,true);
 begin perform public.household_v1('list_payees');raise exception 'OTP read payees';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 begin perform public.household_v1('list_payees');raise exception 'Sessionless directory read';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('create_payee','{"name":"Not authorized"}');raise exception 'Sessionless payee create';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 update household_private.memberships set status='removed' where user_id=actor;
 begin perform public.household_v1('list_payees');raise exception 'Removed member read payees';exception when insufficient_privilege then null;end;
 insert into payee_test_results values('Trash/restore and private approved-passkey access boundaries',true);
end $$;
select * from payee_test_results;
rollback;
