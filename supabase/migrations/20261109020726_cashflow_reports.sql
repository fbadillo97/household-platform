-- Read-only household statistics; no records, classifications or settings are changed.
create function household_private.reports_events(code text,timing text)
 returns table(event_date date,category_id uuid,account_id uuid,series text,amount numeric,transaction_id uuid,peer_id uuid,kind text)
 language sql stable set search_path='' as $$
 select case when e.kind='refund' and timing='purchase' then peer.date else t.date end,
 e.category_id,case when e.kind='refund' then peer.account_id else t.account_id end,
 case when e.kind='refund_remainder' then 'review' when e.kind='outflow' and l.role='income' then 'income' when e.kind='credit' then 'income' when e.kind='refund' and l.role='income' then 'conflict' else 'spending' end,
 case when e.kind='outflow' and l.role='income' then -e.value else e.value end,e.transaction_id,e.peer_id,e.kind
 from household_private.budget_events(code,timing) e
 join household_private.planning_transactions t on t.id=e.transaction_id
 left join household_private.planning_transactions peer on peer.id=e.peer_id
 left join household_private.budget_months m on m.currency=code and m.month=e.event_month
 left join household_private.budget_lines l on l.month_id=m.id and l.category_id=e.category_id
 where e.value<>0 and t.date<=household_private.planning_today()
$$;
create function household_private.reports_summary(start_day date,end_day date,code text,ids uuid[],timing text) returns jsonb
 language plpgsql stable set search_path='' as $$
declare result jsonb;scope text:=household_private.budget_scope(code);
begin
 if exists(select 1 from household_private.reports_events(code,timing) e where e.event_date between start_day and end_day and (cardinality(ids)=0 or e.account_id=any(ids)) and e.series='conflict') then raise exception using errcode='22023',message='A refunded purchase category is planned as income; correct the category or budget plan';end if;
 with events as materialized(select * from household_private.reports_events(code,timing) e where e.event_date between start_day and end_day and (cardinality(ids)=0 or e.account_id=any(ids))),
 periods as(select day::date as month,greatest(day::date,start_day) range_start,least((day+interval '1 month - 1 day')::date,end_day) range_end from generate_series(date_trunc('month',start_day),date_trunc('month',end_day),interval '1 month') day),
 months as(select to_char(p.month,'YYYY-MM') as month,p.range_start as "from",p.range_end as "to",
 household_private.planning_safe(coalesce((select sum(e.amount) from events e where e.series='income' and e.event_date between p.range_start and p.range_end),0)) income_minor,
 household_private.planning_safe(coalesce((select sum(e.amount) from events e where e.series='spending' and e.event_date between p.range_start and p.range_end),0)) spending_minor,
 (select count(*) from events e where e.series='income' and e.event_date between p.range_start and p.range_end) income_entries,
 (select count(*) from events e where e.series='spending' and e.event_date between p.range_start and p.range_end) spending_entries,
 (select count(*) from events e where e.series in ('income','spending') and e.event_date between p.range_start and p.range_end) entry_count,
 p.range_start<>p.month or p.range_end<>(p.month+interval '1 month - 1 day')::date partial_window,
 exists(select 1 from household_private.budget_months b where b.month=p.month and b.currency=code and b.coverage_confirmed_at is not null and b.coverage_account_scope=scope and b.month<date_trunc('month',household_private.planning_today())::date) coverage_confirmed
 from periods p),
 categories as(select e.category_id,coalesce(c.name,'Unassigned') name,household_private.planning_safe(sum(e.amount)) spending_minor,count(*) entry_count from events e left join household_private.categories c on c.id=e.category_id where e.series='spending' group by e.category_id,c.name),
 totals as(select household_private.planning_safe(coalesce(sum(amount) filter(where series='income'),0)) income_minor,household_private.planning_safe(coalesce(sum(amount) filter(where series='spending'),0)) spending_minor,household_private.planning_safe(coalesce(sum(amount) filter(where series='review'),0)) review_minor,count(*) filter(where series in ('income','spending')) entry_count,count(*) filter(where series='review') review_entries from events)
 select jsonb_build_object('from',start_day,'to',end_day,'currency',code,'income_minor',t.income_minor,'spending_minor',t.spending_minor,'surplus_minor',household_private.planning_safe(t.income_minor::numeric-t.spending_minor),
 'entry_count',t.entry_count,'review_minor',t.review_minor,'review_entries',t.review_entries,
 'coverage_confirmed',coalesce((select bool_and(coverage_confirmed) from months),false),
 'months',coalesce((select jsonb_agg(to_jsonb(m) order by m.month) from months m),'[]'::jsonb),
 'categories',coalesce((select jsonb_agg(to_jsonb(c) order by c.spending_minor desc,c.name,c.category_id) from categories c),'[]'::jsonb)) into result from totals t;
 if octet_length(result::text)>8000000 then raise exception using errcode='22023',message='Report is too large; choose a shorter range';end if;return result;
end $$;
create function household_private.reports_dispatch(operation text,payload jsonb default '{}'::jsonb) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();actor_role text:=household_private.member_role();p jsonb:=payload;start_day date;end_day date;previous_start date;previous_end date;code text;timing text;ids uuid[]:='{}';category uuid;selected_series text;off integer;lim integer;result jsonb;
begin
 if operation='reports_overview' then perform household_private.planning_check(p,array['from','to','currency','account_ids','compare_from','compare_to']);
 elsif operation='reports_activity' then perform household_private.planning_check(p,array['from','to','currency','account_ids','series','category_id','offset','limit']);
 else raise exception using errcode='22023',message='Unknown report operation';end if;
 start_day:=household_private.planning_date(p,'from');end_day:=household_private.planning_date(p,'to');code:=household_private.planning_text(p,'currency',3,3);
 if start_day is null or end_day is null or start_day<'1900-01-01' or end_day>household_private.planning_today() or end_day>'2100-12-31' or end_day<start_day or end_day-start_day>731 or code !~ '^[A-Z]{3}$' then raise exception using errcode='22023',message='Choose a report range of up to two years ending today or earlier';end if;
 if p?'account_ids' then
  if jsonb_typeof(p->'account_ids') is distinct from 'array' or jsonb_array_length(p->'account_ids')>100 then raise exception using errcode='22023',message='Choose up to 100 accounts';end if;
  if exists(select 1 from jsonb_array_elements(p->'account_ids') a where jsonb_typeof(a)<>'string') then raise exception using errcode='22023',message='Choose valid account identifiers';end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into ids from jsonb_array_elements_text(p->'account_ids');
  if (select count(distinct id) from unnest(ids) id)<>cardinality(ids) or exists(select 1 from unnest(ids) selected(id) where not exists(select 1 from household_private.accounts a where a.id=selected.id and a.currency=code)) then raise exception using errcode='22023',message='Selected accounts must be distinct and use the report currency';end if;
 end if;
 if (select count(*) from household_private.planning_transactions where currency=code)>50000 then raise exception using errcode='22023',message='Report ledger exceeds the supported limit';end if;
 select coalesce((select refund_timing from household_private.budget_settings where currency=code),'received') into timing;
 if operation='reports_overview' then
  previous_start:=household_private.planning_date(p,'compare_from');previous_end:=household_private.planning_date(p,'compare_to');
  if (previous_start is null)<>(previous_end is null) or (previous_start is not null and (previous_start<'1900-01-01' or previous_end>household_private.planning_today() or previous_end-previous_start<>end_day-start_day)) then raise exception using errcode='22023',message='Comparison must use an equally long valid date range';end if;
  result:=jsonb_build_object('current',household_private.reports_summary(start_day,end_day,code,ids,timing),'comparison',case when previous_start is not null then household_private.reports_summary(previous_start,previous_end,code,ids,timing) end,'refund_timing',timing,
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'currency',a.currency,'archived_at',a.archived_at) order by a.name,a.id) from household_private.accounts a),'[]'::jsonb),
   'currencies',coalesce((select jsonb_agg(currency order by currency) from (select currency from household_private.accounts union select code) c),'[]'::jsonb),
   'invalid_refund_links',(select count(*) from household_private.budget_refund_context c join household_private.planning_transactions t on t.id=c.purchase_id where not c.valid and (c.purchase_currency=code or c.refund_currency=code) and (cardinality(ids)=0 or t.account_id=any(ids)) and (c.purchase_date between start_day and end_day or c.refund_date between start_day and end_day)));
  if octet_length(result::text)>8000000 then raise exception using errcode='22023',message='Report is too large';end if;return result;
 end if;
 selected_series:=household_private.planning_text(p,'series',1,10,'all');if selected_series not in ('all','income','spending','review') then raise exception using errcode='22023',message='Choose a valid report series';end if;
 category:=nullif(p->>'category_id','')::uuid;off:=household_private.planning_int(p,'offset',0,1000000,0);lim:=household_private.planning_int(p,'limit',1,50,50);
 with filtered as materialized(select e.*,t.date bank_date,t.description,t.account_name,t.amount_minor bank_amount_minor,t.currency,peer.description peer_description,peer.date peer_date from household_private.reports_events(code,timing) e join household_private.planning_transactions t on t.id=e.transaction_id left join household_private.planning_transactions peer on peer.id=e.peer_id where e.event_date between start_day and end_day and (cardinality(ids)=0 or e.account_id=any(ids)) and (case when selected_series='all' then e.series in ('income','spending') else e.series=selected_series end) and (not p?'category_id' or e.category_id is not distinct from category)),
 page as(select * from filtered order by event_date desc,transaction_id,peer_id,series limit lim offset off)
 select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg((to_jsonb(r)-'amount')||jsonb_build_object('impact_minor',household_private.planning_safe(r.amount)) order by r.event_date desc,r.transaction_id,r.peer_id,r.series) from page r),'[]'::jsonb)) into result;return result;
end $$;
revoke all on function household_private.reports_events(text,text),household_private.reports_summary(date,date,text,uuid[],text),household_private.reports_dispatch(text,jsonb) from public,anon,authenticated;
grant execute on function household_private.reports_dispatch(text,jsonb) to authenticated;
create function public.household_reports_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select household_private.reports_dispatch(operation,payload)$$;
revoke all on function public.household_reports_v1(text,jsonb) from public,anon,authenticated;
grant execute on function public.household_reports_v1(text,jsonb) to authenticated;
notify pgrst,'reload schema';
