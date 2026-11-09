-- Administrative rollback-only tests with fabricated users and reserved test currencies.
begin;
create temporary table reports_test_results(name text,passed boolean);
do $$
declare actor uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();bank uuid;card uuid;foreign_account uuid;food uuid;pay uuid;purchase uuid;refund uuid;salary uuid;credit uuid;tx uuid;report jsonb;source jsonb;link uuid;before_count integer;
begin
 insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at,updated_at) values(actor,'mock-reports-'||actor||'@example.invalid',now(),false,now(),now());insert into household_private.memberships(user_id,status,role) values(actor,'approved','member');insert into auth.sessions(id,user_id,aal) values(sid,actor,'aal1');insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),sid,'passkey',now(),now());perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',sid,'role','authenticated')::text,true);
 insert into household_private.accounts(name,kind,currency) values('Mock report bank '||actor,'checking','XTR') returning id into bank;
 insert into household_private.accounts(name,kind,currency) values('Mock report card '||actor,'credit','XTR') returning id into card;
 insert into household_private.accounts(name,kind,currency) values('Mock foreign report '||actor,'checking','YTR') returning id into foreign_account;
 insert into household_private.categories(name) values('Mock report food '||actor) returning id into food;insert into household_private.categories(name) values('Mock report pay '||actor) returning id into pay;
 insert into household_private.transactions(account_id,category_id,date,description,amount_minor,fingerprint) values(bank,food,'2026-08-10','Mock purchase',-12000,'mock-report-p-'||actor) returning id into purchase;
 insert into household_private.transactions(account_id,category_id,date,description,amount_minor,fingerprint) values(card,food,'2026-09-10','Mock refund credited elsewhere',4000,'mock-report-r-'||actor) returning id into refund;
 insert into household_private.transactions(account_id,category_id,date,description,amount_minor,fingerprint) values(bank,pay,'2026-08-01','Mock salary',100000,'mock-report-s-'||actor) returning id into salary;
 insert into household_private.transactions(account_id,category_id,date,description,amount_minor,fingerprint) values(bank,food,'2026-09-15','Mock other purchase',-2000,'mock-report-o-'||actor);
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(foreign_account,'2026-08-10','Mock foreign spending',-90000,'mock-report-f-'||actor);
 -- Existing transfer handling must stay excluded.
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(bank,'2026-08-11','Mock transfer out',-7000,'mock-report-t1-'||actor) returning id into tx;
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint) values(card,'2026-08-11','Mock transfer in',7000,'mock-report-t2-'||actor) returning id into credit;
 perform public.household_v1('link_transfer',jsonb_build_object('id',tx,'revision',1,'peer_id',credit,'peer_revision',1,'flow_type','transfer'));
 select to_jsonb(t) into source from household_private.transactions t where id=purchase;
 report:=public.household_budget_v1('budget_link_refund',jsonb_build_object('currency','XTR','purchase_id',purchase,'purchase_revision',1,'refund_id',refund,'refund_revision',1,'amount_minor',4000));link:=(report->>'id')::uuid;
 report:=public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-09-30","currency":"XTR","account_ids":[],"compare_from":"2026-06-01","compare_to":"2026-07-31"}');
 if report->'current'->>'income_minor'<>'100000' or report->'current'->>'spending_minor'<>'10000' or report->'current'->>'surplus_minor'<>'90000' then raise exception 'Whole-period net totals, transfer or currency exclusion failed: %',report->'current';end if;
 if report->'current'->>'coverage_confirmed'<>'false' or jsonb_array_length(report->'current'->'months')<>2 then raise exception 'Coverage/month shape failed';end if;
 if report->'current'->'months'->1->>'spending_minor'<>'-2000' then raise exception 'Net-credit month was hidden';end if;
 report:=public.household_reports_v1('reports_overview',jsonb_build_object('from','2026-09-01','to','2026-09-30','currency','XTR','account_ids',jsonb_build_array(bank)));
 if report->'current'->>'spending_minor'<>'-2000' or report->'current'->>'income_minor'<>'0' then raise exception 'Refund did not follow purchase account';end if;
 report:=public.household_reports_v1('reports_activity',jsonb_build_object('from','2026-09-01','to','2026-09-30','currency','XTR','account_ids',jsonb_build_array(bank),'series','spending','category_id',food,'offset',0,'limit',1));
 if report->>'total'<>'2' or jsonb_array_length(report->'rows')<>1 then raise exception 'Activity pagination/count failed';end if;
 report:=public.household_reports_v1('reports_activity',jsonb_build_object('from','2026-09-01','to','2026-09-30','currency','XTR','account_ids',jsonb_build_array(bank),'series','spending','category_id',food,'offset',1,'limit',50));
 if not exists(select 1 from jsonb_array_elements(report->'rows') e where e->>'transaction_id'=refund::text and e->>'peer_id'=purchase::text and e->>'impact_minor'='-4000') then raise exception 'Refund source/peer or allocation lost';end if;
 if (select to_jsonb(t) from household_private.transactions t where id=purchase)<>source then raise exception 'Read report changed source';end if;
 -- Budget policy determines cross-month assignment but is not changed by reporting.
 perform public.household_budget_v1('budget_create_month','{"month":"2026-08","currency":"XTR","refund_timing":"purchase","settings_revision":0,"copy_from":null}');
 report:=public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-08-31","currency":"XTR"}');if report->'current'->>'spending_minor'<>'8000' or report->>'refund_timing'<>'purchase' then raise exception 'Original-purchase report timing failed';end if;
 perform public.household_budget_v1('budget_confirm_coverage','{"month":"2026-08","currency":"XTR","plan_revision":1,"confirmed":true}');
 report:=public.household_reports_v1('reports_overview','{"from":"2026-08-05","to":"2026-08-12","currency":"XTR"}');if report->'current'->>'coverage_confirmed'<>'true' or report->'current'->'months'->0->>'partial_window'<>'true' then raise exception 'Confirmed coverage and selected partial window conflated';end if;
 -- Remaining known credits must not inflate income; refunds and corrections keep exact signs.
 update household_private.transactions set amount_minor=5000 where id=refund;
 insert into household_private.budget_lines(month_id,category_id,role,planned_minor,rollover_mode) select id,pay,'income',100000,'reset' from household_private.budget_months where currency='XTR' and month='2026-08-01';
 insert into household_private.transactions(account_id,category_id,date,description,amount_minor,fingerprint) values(bank,pay,'2026-08-02','Mock income correction',-1000,'mock-report-correction-'||actor);
 insert into household_private.transactions(account_id,date,description,amount_minor,fingerprint,deleted_at) values(bank,'2026-08-02','Mock trashed expense',-80000,'mock-report-trash-'||actor,now());
 report:=public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-09-30","currency":"XTR"}');
 if report->'current'->>'income_minor'<>'99000' or report->'current'->>'spending_minor'<>'10000' or report->'current'->>'review_minor'<>'1000' or report->'current'->>'review_entries'<>'1' then raise exception 'Income correction, Trash or refund remainder misclassified: %',report->'current';end if;
 insert into reports_test_results values('income corrections, Trash and known refund remainders retain correct accounting signs',true);
 insert into reports_test_results values('exact monthly/category totals, refunds, transfers, currencies, purchase-account attribution and source pagination',true),('budget refund timing, read-only source invariants and honest partial/confirmed coverage',true);
 begin perform public.household_reports_v1('reports_overview','{"from":"2026-09-01","to":"2026-08-01","currency":"XTR"}');raise exception 'Reversed range allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-08-31","currency":"XTR","compare_from":"2026-07-01","compare_to":"2026-07-30"}');raise exception 'Unequal comparison allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_reports_v1('reports_overview',jsonb_build_object('from','2026-08-01','to','2026-08-31','currency','XTR','account_ids',jsonb_build_array(foreign_account)));raise exception 'Foreign currency account allowed';exception when invalid_parameter_value then null;end;
 begin perform public.household_reports_v1('reports_overview',jsonb_build_object('from','2026-08-01','to','2026-08-31','currency','XTR','account_ids',jsonb_build_array(gen_random_uuid())));raise exception 'Unknown account accepted';exception when invalid_parameter_value then null;end;
 begin perform public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-08-31","currency":"XTR","sql":"Forbidden"}');raise exception 'Arbitrary fields allowed';exception when invalid_parameter_value then null;end;
 if has_function_privilege('authenticated','household_private.reports_events(text,text)','EXECUTE') or has_function_privilege('anon','public.household_reports_v1(text,jsonb)','EXECUTE') then raise exception 'Private report helper/anonymous API exposed';end if;
 execute 'set local role authenticated';perform public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-08-31","currency":"XTR"}');execute 'reset role';
 update household_private.memberships set status='removed' where user_id=actor;
 begin perform public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-08-31","currency":"XTR"}');raise exception 'Removed member read reports';exception when insufficient_privilege then null;end;
 update household_private.memberships set status='approved' where user_id=actor;perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',gen_random_uuid(),'role','authenticated')::text,true);
 begin perform public.household_reports_v1('reports_overview','{"from":"2026-08-01","to":"2026-08-31","currency":"XTR"}');raise exception 'Revoked/missing session read reports';exception when insufficient_privilege then null;end;
 insert into reports_test_results values('strict dates/comparisons/accounts/fields and authenticated private passkey/session access',true);
end $$;
select * from reports_test_results order by name;
rollback;
