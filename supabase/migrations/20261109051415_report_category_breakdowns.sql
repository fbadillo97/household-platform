-- Read-only category totals from the same checked reporting events. No records or permissions change.
create or replace function household_private.reports_summary(start_day date,end_day date,code text,ids uuid[],timing text) returns jsonb
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
 income_categories as(select e.category_id,coalesce(c.name,'Unassigned') name,household_private.planning_safe(sum(e.amount)) income_minor,count(*) entry_count from events e left join household_private.categories c on c.id=e.category_id where e.series='income' group by e.category_id,c.name),
 totals as(select household_private.planning_safe(coalesce(sum(amount) filter(where series='income'),0)) income_minor,household_private.planning_safe(coalesce(sum(amount) filter(where series='spending'),0)) spending_minor,household_private.planning_safe(coalesce(sum(amount) filter(where series='review'),0)) review_minor,count(*) filter(where series in ('income','spending')) entry_count,count(*) filter(where series='review') review_entries from events)
 select jsonb_build_object('from',start_day,'to',end_day,'currency',code,'income_minor',t.income_minor,'spending_minor',t.spending_minor,'surplus_minor',household_private.planning_safe(t.income_minor::numeric-t.spending_minor),
 'entry_count',t.entry_count,'review_minor',t.review_minor,'review_entries',t.review_entries,
 'coverage_confirmed',coalesce((select bool_and(coverage_confirmed) from months),false),
 'months',coalesce((select jsonb_agg(to_jsonb(m) order by m.month) from months m),'[]'::jsonb),
 'income_categories',coalesce((select jsonb_agg(to_jsonb(c) order by c.income_minor desc,c.name,c.category_id) from income_categories c),'[]'::jsonb),
 'categories',coalesce((select jsonb_agg(to_jsonb(c) order by c.spending_minor desc,c.name,c.category_id) from categories c),'[]'::jsonb)) into result from totals t;
 if octet_length(result::text)>8000000 then raise exception using errcode='22023',message='Report is too large; choose a shorter range';end if;return result;
end $$;
revoke all on function household_private.reports_summary(date,date,text,uuid[],text) from public,anon,authenticated;
notify pgrst,'reload schema';
