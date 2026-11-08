-- Administrative connection only. All mock fixtures and private source-snapshot checks are rolled back.
begin;
create temporary table transfer_test_results(name text,passed boolean);
do $$
declare actor uuid;sid uuid;a uuid;b uuid;card uuid;usd uuid;tx uuid;peer uuid;bad uuid;wrong_currency uuid;same_account uuid;late uuid;standalone uuid;owner uuid;snapshot uuid;r jsonb;p jsonb;n integer;
begin
 -- A fabricated approved member and server-side passkey session; everything is rolled back.
 actor:=gen_random_uuid();insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at,updated_at) values(actor,'mock-transfer@example.invalid',now(),false,now(),now());
 insert into household_private.memberships(user_id,status,role) values(actor,'approved','member');
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency,source,external_id) values('Mock funding','checking','CAD','monarch','mock-transfer-account') returning id into a;
 insert into household_private.accounts(name,kind,currency) values('Mock savings','savings','CAD') returning id into b;
 insert into household_private.accounts(name,kind,currency) values('Mock card','credit','CAD') returning id into card;
 insert into household_private.accounts(name,kind,currency) values('Mock foreign','savings','USD') returning id into usd;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,source,external_id,source_data) values(a,'2026-10-01','Mock payment',-10000,'mock-transfer-out','monarch','mock-transfer-out','{"tags":["Mock tag"],"notes":"Mock source note"}') returning id into tx;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(card,'2026-10-03','Mock payment received',10000,'mock-transfer-in') returning id into peer;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(b,'2026-10-03','Mock wrong amount',9000,'mock-transfer-bad') returning id into bad;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(usd,'2026-10-03','Mock foreign amount',10000,'mock-transfer-usd') returning id into wrong_currency;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(a,'2026-10-03','Mock same account',10000,'mock-transfer-same') returning id into same_account;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(b,'2026-12-03','Mock late amount',10000,'mock-transfer-late') returning id into late;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(card,'2026-10-03','Mock standalone card payment',500,'mock-transfer-standalone') returning id into standalone;
 r:=public.household_v1('list_transfer_candidates',jsonb_build_object('id',tx));
 if r->>'total'<>'1' or r->'rows'->0->>'id'<>peer::text or r->'rows'->0->>'suggested_type'<>'credit_card_payment' then raise exception 'Candidate amount/currency/account/date scope failed';end if;
 begin perform public.household_v1('link_transfer',jsonb_build_object('id',tx,'revision',1,'peer_id',peer,'peer_revision',2,'flow_type','credit_card_payment'));raise exception 'Stale peer accepted';exception when serialization_failure then null;end;
 foreach n in array array[1,2,3,4] loop
  begin
   perform public.household_v1('link_transfer',jsonb_build_object('id',tx,'revision',1,'peer_id',case n when 1 then bad when 2 then wrong_currency when 3 then same_account else late end,'peer_revision',1,'flow_type','transfer'));
   raise exception 'Invalid pair accepted';
  exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.household_v1('link_transfer',jsonb_build_object('id',tx,'revision',1,'peer_id',tx,'peer_revision',1,'flow_type','transfer'));raise exception 'Self link accepted';exception when invalid_parameter_value then null;end;
 insert into transfer_test_results values('candidates scoped by amount, currency, effective accounts and dates; stale/invalid pairs denied',true);
 r:=public.household_v1('link_transfer',jsonb_build_object('id',tx,'revision',1,'peer_id',peer,'peer_revision',1,'flow_type','credit_card_payment'));
 if r->>'flow_type'<>'credit_card_payment' or r->>'transfer_peer_id'<>peer::text or r->'transfer_peer'->>'revision'<>'2' then raise exception 'Link metadata failed';end if;
 p:=public.household_v1('get_transaction_detail',jsonb_build_object('id',peer));
 if p->>'transfer_peer_id'<>tx::text or p->>'flow_type'<>'credit_card_payment' then raise exception 'Reciprocal link failed';end if;
 if r->>'original_description'<>'Mock payment' or r->>'external_id'<>'mock-transfer-out' or r->'source_data'->>'notes'<>'Mock source note' then raise exception 'Original source changed';end if;
 if public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',a,'flow','credit_card_payment'))->>'total'<>'1' then raise exception 'Flow filter missing pair';end if;
 if public.household_v1('list_transfer_candidates',jsonb_build_object('id',tx))->>'total'<>'0' then raise exception 'Linked anchor still suggested';end if;
 begin perform public.household_v1('trash_transaction',jsonb_build_object('id',tx,'revision',2));raise exception 'Linked trash allowed';exception when serialization_failure then null;end;
 begin perform public.household_v1('set_transaction_flow',jsonb_build_object('id',peer,'revision',2,'flow_type','regular'));raise exception 'Linked single edit allowed';exception when serialization_failure then null;end;
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',2,'account_override_id',b));raise exception 'Linked account move allowed';exception when serialization_failure then null;end;
 perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',tx,'revision',2,'notes','Mock local note'));
 select owner_user_id into owner from household_private.settings where singleton;
 snapshot:=household_private.monarch_stage(jsonb_build_object('account',jsonb_build_object('external_id','mock-transfer-account','name','Mock funding','kind','checking','currency','CAD'),'period_start','2026-10-01','period_end','2026-10-31','expected_count',1,'transactions',jsonb_build_array(jsonb_build_object('external_id','mock-transfer-out','account_external_id','mock-transfer-account','pending',false,'date','2026-10-01','description','Mock payment','amount_minor',-10000,'source_data','{}'::jsonb))),owner,'assistant');
 r:=household_private.monarch_commit(snapshot,owner);
 if r->>'inserted'<>'0' or (select transfer_peer_id<>peer or flow_type<>'credit_card_payment' or notes<>'Mock local note' from household_private.transactions where id=tx) then raise exception 'Reimport lost link/classification/notes';end if;
 insert into transfer_test_results values('atomic reciprocal pairing survives reimport, preserves source and protects pair integrity while notes remain editable',true);
 r:=public.household_v1('unlink_transfer',jsonb_build_object('id',tx,'revision',3,'peer_id',peer,'peer_revision',2));
 p:=public.household_v1('get_transaction_detail',jsonb_build_object('id',peer));
 if r->>'flow_type'<>'regular' or r->>'transfer_peer_id' is not null or p->>'flow_type'<>'regular' or p->>'transfer_peer_id' is not null then raise exception 'Undo failed to restore both sides';end if;
 r:=public.household_v1('set_transaction_flow',jsonb_build_object('id',tx,'revision',4,'flow_type','credit_card_payment'));
 if r->>'flow_type'<>'credit_card_payment' or public.household_v1('list_ledger_transactions',jsonb_build_object('account_id',a,'flow','unlinked_transfer'))->>'total'<>'1' then raise exception 'Single-side classification failed';end if;
 begin perform public.household_v1('set_transaction_flow',jsonb_build_object('id',same_account,'revision',1,'flow_type','credit_card_payment'));raise exception 'Incoming checking marked as card payment';exception when invalid_parameter_value then null;end;
 r:=public.household_v1('set_transaction_flow',jsonb_build_object('id',tx,'revision',5,'flow_type','regular'));
 if r->>'notes'<>'Mock local note' then raise exception 'Classification reset lost notes';end if;
 perform public.household_v1('set_transaction_flow',jsonb_build_object('id',standalone,'revision',1,'flow_type','credit_card_payment'));
 begin perform public.household_v1('update_ledger_transaction',jsonb_build_object('id',standalone,'revision',2,'account_override_id',b));raise exception 'Account move invalidated card payment direction';exception when invalid_parameter_value then null;end;
 -- A missing/trashed peer cannot be linked; restoring a single-sided transfer preserves its type.
 perform public.household_v1('trash_transaction',jsonb_build_object('id',peer,'revision',3));
 if public.household_v1('list_transfer_candidates',jsonb_build_object('id',tx))->>'total'<>'0' then raise exception 'Trash appeared as candidate';end if;
 begin perform public.household_v1('link_transfer',jsonb_build_object('id',tx,'revision',6,'peer_id',peer,'peer_revision',4,'flow_type','credit_card_payment'));raise exception 'Trashed peer linked';exception when serialization_failure then null;end;
 perform public.household_v1('set_transaction_flow',jsonb_build_object('id',tx,'revision',6,'flow_type','transfer'));
 perform public.household_v1('trash_transaction',jsonb_build_object('id',tx,'revision',7));
 r:=public.household_v1('restore_transaction',jsonb_build_object('id',tx,'revision',8));
 if r->>'flow_type'<>'transfer' then raise exception 'Restore lost single-side classification';end if;
 insert into transfer_test_results values('undo resets both sides; standalone classification, direction and Trash/Restore rules pass',true);
 -- API privilege boundaries hold for new operations too.
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'otp',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 begin perform public.household_v1('list_transfer_candidates',jsonb_build_object('id',tx));raise exception 'OTP read candidates';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('set_transaction_flow',jsonb_build_object('id',tx,'revision',9,'flow_type','regular'));raise exception 'OTP classification';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('link_transfer',jsonb_build_object('id',tx,'revision',9,'peer_id',peer,'peer_revision',4,'flow_type','transfer'));raise exception 'OTP linking';exception when insufficient_privilege then null;end;
 begin perform public.household_v1('unlink_transfer',jsonb_build_object('id',tx,'revision',9,'peer_id',peer,'peer_revision',4));raise exception 'OTP unlinking';exception when insufficient_privilege then null;end;
 if has_function_privilege('authenticated','household_private.transfer_action(text,jsonb)','EXECUTE') or has_function_privilege('anon','household_private.transfer_candidates(jsonb)','EXECUTE') then raise exception 'Private helper exposed';end if;
 insert into transfer_test_results values('new operations require approved live passkey sessions and private helper grants stay revoked',true);
end $$;
select * from transfer_test_results order by name;
rollback;
