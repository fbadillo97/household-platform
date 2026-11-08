-- Administrative connection only. All member, session, account and snapshot fixtures are fabricated and rolled back.
begin;
create temporary table history_test_results(name text,passed boolean);
do $$
declare actor uuid;sid uuid;passkey_sid uuid;bank uuid;card uuid;missing uuid;excluded uuid;archived uuid;foreign_id uuid;r jsonb;start_day date:=current_date-30;finish date:=current_date;item jsonb;
begin
 actor:=gen_random_uuid();insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at,updated_at) values(actor,'mock-history@example.invalid',now(),false,now(),now());
 insert into household_private.memberships(user_id,status,role) values(actor,'approved','member');
 sid:=gen_random_uuid();passkey_sid:=sid;insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency) values('Mock history bank','checking','XTS') returning id into bank;
 insert into household_private.accounts(name,kind,currency) values('Mock history card','credit','XTS') returning id into card;
 insert into household_private.accounts(name,kind,currency) values('Mock history missing','savings','XTS') returning id into missing;
 insert into household_private.accounts(name,kind,currency,include_in_net_worth) values('Mock history excluded','investment','XTS',false) returning id into excluded;
 insert into household_private.accounts(name,kind,currency,archived_at) values('Mock history archived','asset','XTS',now()) returning id into archived;
 insert into household_private.accounts(name,kind,currency) values('Mock history foreign','checking','USD') returning id into foreign_id;
 insert into household_private.account_balance_snapshots(account_id,as_of,amount_minor,currency,note,created_by) values
  (bank,start_day-10,10000,'XTS','Mock seed',actor),(bank,start_day+10,20000,'XTS','Mock older version',actor),(bank,start_day+10,25000,'XTS','Mock correction',actor),
  (card,start_day+15,7000,'XTS','Mock liability',actor),(excluded,start_day,50000,'XTS','Mock excluded',actor),(archived,start_day,90000,'XTS','Mock archive',actor),(foreign_id,start_day,80000,'USD','Mock foreign',actor);
 r:=public.household_v1('get_balance_history',jsonb_build_object('scope','net_worth','currency','XTS','from',start_day,'to',finish));
 if jsonb_array_length(r->'accounts')<>3 or jsonb_array_length(r->'entries')<>3 or r->>'cohort_policy'<>'current_inclusion' then raise exception 'Cohort/currency/latest correction scope failed';end if;
 if not exists(select 1 from jsonb_array_elements(r->'entries') e where e->>'account_id'=bank::text and e->>'as_of'=(start_day-10)::text and e->>'carry_in'='true') then raise exception 'Carry-in seed missing';end if;
 if not exists(select 1 from jsonb_array_elements(r->'entries') e where e->>'account_id'=bank::text and e->>'amount_minor'='25000' and e->>'correction_count'='1') then raise exception 'Same-day newest correction not chosen';end if;
 if exists(select 1 from jsonb_array_elements(r->'entries') e where e->>'note' is not null) then raise exception 'Aggregate history unnecessarily exposed notes';end if;
 r:=public.household_v1('get_balance_history',jsonb_build_object('scope','net_worth','currency','XTS','from',null,'to',finish));
 if r->>'from'<>(start_day-10)::text or r->>'earliest_available'<>(start_day-10)::text then raise exception 'All range start is not earliest actual entry';end if;
 r:=public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',archived,'from',start_day,'to',finish));
 if jsonb_array_length(r->'accounts')<>1 or r->'accounts'->0->>'archived_at' is null or r->'entries'->0->>'note'<>'Mock archive' then raise exception 'Individual archived history unavailable';end if;
 r:=public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',excluded,'from',start_day,'to',finish));
 if r->'accounts'->0->>'include_in_net_worth'<>'false' or jsonb_array_length(r->'entries')<>1 then raise exception 'Excluded individual history unavailable';end if;
 r:=public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',missing,'from',start_day,'to',finish));
 if jsonb_array_length(r->'entries')<>0 or r->'earliest_available'<>'null'::jsonb then raise exception 'Missing balance fabricated history';end if;
 r:=public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',bank,'from',start_day-20,'to',start_day-11));
 if jsonb_array_length(r->'entries')<>0 then raise exception 'Future record backfilled into earlier range';end if;
 insert into history_test_results values('current cohort/currency, carry-in seeds, same-day corrections, actual all-range bounds, individual archives and genuine missing history',true);
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','net_worth','currency','XTS','from',finish,'to',start_day));raise exception 'Reversed range allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','net_worth','currency','XTS','to',finish+1));raise exception 'Future range allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','net_worth','currency','XTS','from','2026-02-30'));raise exception 'Impossible date allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',bank,'currency','USD'));raise exception 'Mismatched currency allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',gen_random_uuid()));raise exception 'Missing account accepted';exception when no_data_found then null;end;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','net_worth','currency','XTS','sql','Forbidden'));raise exception 'Unknown payload accepted';exception when invalid_parameter_value then null;end;
 insert into household_private.account_balance_snapshots(account_id,as_of,amount_minor,currency,created_by)
  select bank,current_date-n,1,'XTS',actor from generate_series(0,10000) n;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',bank,'from',null,'to',finish));raise exception 'Unbounded history accepted';exception when invalid_parameter_value then null;end;
 insert into household_private.accounts(name,kind,currency) select 'Mock history cap '||n,'checking','XTS' from generate_series(1,501) n;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','net_worth','currency','XTS','from',start_day,'to',finish));raise exception 'Unbounded cohort accepted';exception when invalid_parameter_value then null;end;
 insert into history_test_results values('strict input/date/currency validation and bounded history/cohort reject without silently truncating',true);
 sid:=gen_random_uuid();insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'otp',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated','amr',jsonb_build_array('passkey'))::text,true);
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',bank));raise exception 'OTP history allowed';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',passkey_sid,'role','authenticated')::text,true);
 update household_private.memberships set status='removed' where user_id=actor;
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',bank));raise exception 'Removed member read history';exception when insufficient_privilege then null;end;
 update household_private.memberships set status='approved' where user_id=actor;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',gen_random_uuid(),'role','authenticated')::text,true);
 begin perform public.household_v1('get_balance_history',jsonb_build_object('scope','account','account_id',bank));raise exception 'Missing server session read history';exception when insufficient_privilege then null;end;
 if has_function_privilege('authenticated','household_private.balance_history(jsonb)','EXECUTE') or has_function_privilege('anon','household_private.balance_history(jsonb)','EXECUTE') or has_table_privilege('authenticated','household_private.account_balance_snapshots','SELECT') then raise exception 'Private history helper/table exposed';end if;
 insert into history_test_results values('OTP/spoofed claims, removed membership, missing server sessions and direct helper/table access stay denied',true);
end $$;
select * from history_test_results order by name;
rollback;
