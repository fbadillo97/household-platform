-- Filter-consistent full-ledger summary; existing financial records are unchanged.
create or replace function household_private.ledger_query(payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 _role text:=household_private.member_role();_limit integer:=coalesce((payload->>'limit')::integer,50);_offset integer:=coalesce((payload->>'offset')::integer,0);
 _sort text:=coalesce(payload->>'sort','date');_direction text:=coalesce(payload->>'direction','desc');_trash boolean:=coalesce((payload->>'trash_only')::boolean,false);_review text:=coalesce(payload->>'review','');_flow text:=coalesce(payload->>'flow','');
 _account uuid:=nullif(payload->>'account_id','')::uuid;_payee uuid:=nullif(nullif(payload->>'payee_id','__unassigned'),'')::uuid;_category uuid:=nullif(nullif(payload->>'category_id','__unassigned'),'')::uuid;
 _from date:=(payload->>'date_from')::date;_to date:=(payload->>'date_to')::date;
 _min bigint:=(payload->>'min_minor')::bigint;_max bigint:=(payload->>'max_minor')::bigint;result jsonb;
begin
 if _limit not between 1 and 500 or _offset not between 0 and 1000000 or _sort not in ('date','description','account','amount','category','tags','payee') or _direction not in ('asc','desc') then
  raise exception using errcode='22023',message='Invalid sort or pagination';end if;
 if _flow not in ('','regular','transfer','credit_card_payment','unlinked_transfer') then raise exception using errcode='22023',message='Invalid transaction type filter';end if;
 if _review not in ('','unreviewed','reviewed','needs_attention') then raise exception using errcode='22023',message='Invalid review filter';end if;
 if (_from is not null and _to is not null and _from>_to) or (_min is not null and _max is not null and _min>_max)
  or coalesce(payload->>'month','') !~ '^([0-9]{4}-(0[1-9]|1[0-2]))?$'
  or length(coalesce(payload->>'query',''))>500 or length(coalesce(payload->>'description',''))>500 or length(coalesce(payload->>'tags',''))>200 then
  raise exception using errcode='22023',message='Check the date, amount or text filters';end if;
 with effective as (
  select t.id,t.date,t.amount_minor,t.category_id,t.payee_id,t.flow_type,t.transfer_peer_id,t.notes,t.review_status,t.needs_attention,t.deleted_at,coalesce(t.account_override_id,t.account_id) as effective_account,
   coalesce(t.description_override,t.description) as effective_description,a.currency,a.name as account_name,c.name as category_name,p.name as payee_name,tag_names.terms as tags_text,
   to_jsonb(t)||jsonb_build_object('description',coalesce(t.description_override,t.description),'account_id',coalesce(t.account_override_id,t.account_id),
    'original_description',t.description,'original_account_id',t.account_id,'account_name',a.name,'category_name',c.name,'payee_name',p.name,'tags_text',tag_names.terms,
    'receipt_count',(select count(*) from household_private.receipts r where r.transaction_id=t.id and r.state='ready' and r.removed_at is null),'has_description_override',t.description_override is not null,'has_account_override',t.account_override_id is not null) as row_data
  from household_private.transactions t
  join household_private.accounts a on a.id=coalesce(t.account_override_id,t.account_id)
  left join household_private.categories c on c.id=t.category_id
  left join household_private.payees p on p.id=t.payee_id
  left join lateral(select coalesce(string_agg(case when jsonb_typeof(tag)='string' then tag#>>'{}' else coalesce(tag->>'name',tag->>'id','') end,' '),'') as terms
   from jsonb_array_elements(case when t.tags_override is not null then to_jsonb(t.tags_override) when jsonb_typeof(t.source_data->'tags')='array' then t.source_data->'tags' else '[]'::jsonb end) tag) tag_names on true
 ), filtered as materialized (
  select * from effective e where ((_trash and e.deleted_at is not null) or (not _trash and e.deleted_at is null))
   and (_flow='' or (_flow='unlinked_transfer' and e.flow_type<>'regular' and e.transfer_peer_id is null) or e.flow_type=_flow)
   and (_review='' or (_review='needs_attention' and e.needs_attention) or e.review_status=_review) and (_account is null or e.effective_account=_account)
   and (coalesce(payload->>'category_id','')<>'__unassigned' or e.category_id is null) and (_category is null or e.category_id=_category)
   and (coalesce(payload->>'payee_id','')<>'__unassigned' or e.payee_id is null) and (_payee is null or e.payee_id=_payee)
   and (coalesce(payload->>'automation_source','')='' or exists(select 1 from household_private.automation_events ae where ae.transaction_id=e.id and ae.source_key=payload->>'automation_source' and ae.status='applied'))
   and (coalesce(payload->>'automation_event','')='' or exists(select 1 from household_private.automation_events ae where ae.transaction_id=e.id and ae.id=(payload->>'automation_event')::uuid))
   and (_from is null or e.date>=_from) and (_to is null or e.date<=_to)
   and (coalesce(payload->>'month','')='' or to_char(e.date,'YYYY-MM')=payload->>'month')
   and (_min is null or e.amount_minor>=_min) and (_max is null or e.amount_minor<=_max)
   and strpos(lower(e.effective_description),lower(coalesce(payload->>'description','')))>0
   and strpos(lower(e.tags_text),lower(coalesce(payload->>'tags','')))>0
   and strpos(lower(concat_ws(' ',e.effective_description,e.account_name,e.category_name,e.payee_name,e.tags_text,e.notes)),lower(coalesce(payload->>'query','')))>0
 ), income_categories as materialized (
  select bm.currency,bm.month,bl.category_id from household_private.budget_months bm join household_private.budget_lines bl on bl.month_id=bm.id where bl.role='income'
 ), valid_refunds as materialized (
  select r.refund_id,sum(r.amount_minor::numeric) as refund_minor,bool_or(ic.category_id is not null) as income_conflict
  from household_private.budget_refund_context r left join income_categories ic on ic.currency=r.purchase_currency and ic.month=date_trunc('month',r.refund_date)::date and ic.category_id=r.category_id where r.valid group by r.refund_id
 ), known_refunds as materialized (
  select distinct refund_id from household_private.budget_refund_links where unlinked_at is null
 ), annotated as materialized (
  select f.*,f.flow_type='regular' and f.amount_minor<0 and ic.category_id is null as is_expense,
   kr.refund_id is not null as known_refund,coalesce(r.refund_minor,0) as refund_minor,coalesce(r.income_conflict,false) and f.flow_type='regular' and f.amount_minor>0 as income_refund_conflict
  from filtered f left join income_categories ic on ic.currency=f.currency and ic.month=date_trunc('month',f.date)::date and ic.category_id=f.category_id
  left join valid_refunds r on r.refund_id=f.id left join known_refunds kr on kr.refund_id=f.id
 ), money_stats as (
  select currency,count(*) as transaction_count,count(*) filter(where flow_type<>'regular') as transfer_count,
   household_private.planning_safe(coalesce(sum(case when flow_type<>'regular' then 0 when amount_minor<0 and not is_expense then amount_minor::numeric when amount_minor>0 and not known_refund then amount_minor::numeric else 0 end),0)) as income_minor,
   household_private.planning_safe(coalesce(sum(-amount_minor::numeric) filter(where is_expense),0)-coalesce(sum(refund_minor) filter(where flow_type='regular' and amount_minor>0),0)) as spending_minor,
   case when count(*) filter(where flow_type='regular')>0 then household_private.planning_safe(round(avg(abs(amount_minor::numeric)) filter(where flow_type='regular'))) end as average_transaction_minor,
   case when count(*) filter(where is_expense)>0 then household_private.planning_safe(round(avg(-amount_minor::numeric) filter(where is_expense))) end as average_expense_minor,
   household_private.planning_safe(coalesce(sum(refund_minor) filter(where flow_type='regular' and amount_minor>0),0)) as refunds_minor,
   household_private.planning_safe(coalesce(sum(greatest(amount_minor::numeric-refund_minor,0)) filter(where flow_type='regular' and amount_minor>0 and known_refund),0)) as review_credits_minor
  from annotated group by currency
 ), summary_money as (
  select to_jsonb(m)||jsonb_build_object('net_minor',household_private.planning_safe(m.income_minor::numeric-m.spending_minor),
   'largest_expense',(select jsonb_build_object('id',a.id,'date',a.date,'description',a.effective_description,'currency',a.currency,'amount_minor',a.amount_minor,'account_name',a.account_name) from annotated a where a.currency=m.currency and a.is_expense order by a.amount_minor asc,a.date,a.id limit 1),
   'smallest_expense',(select jsonb_build_object('id',a.id,'date',a.date,'description',a.effective_description,'currency',a.currency,'amount_minor',a.amount_minor,'account_name',a.account_name) from annotated a where a.currency=m.currency and a.is_expense order by a.amount_minor desc,a.date,a.id limit 1)) as value,m.currency
  from money_stats m
 ), ordered as (
  select *,row_number() over(order by
   case when _sort='date' and _direction='asc' then date end asc,
   case when _sort='date' and _direction='desc' then date end desc,
   case when _sort='amount' and _direction='asc' then amount_minor end asc,
   case when _sort='amount' and _direction='desc' then amount_minor end desc,
   case when _direction='asc' then case _sort when 'description' then lower(effective_description) when 'account' then lower(account_name) when 'category' then lower(coalesce(category_name,'')) when 'payee' then lower(coalesce(payee_name,'')) when 'tags' then lower(tags_text) end end asc,
   case when _direction='desc' then case _sort when 'description' then lower(effective_description) when 'account' then lower(account_name) when 'category' then lower(coalesce(category_name,'')) when 'payee' then lower(coalesce(payee_name,'')) when 'tags' then lower(tags_text) end end desc,
   id asc) as position from filtered
 )
 select jsonb_build_object('summary',jsonb_build_object('transaction_count',(select count(*) from filtered),'needs_attention_count',(select count(*) from filtered where needs_attention),'transfer_count',(select count(*) from filtered where flow_type<>'regular'),'trash_only',_trash,
 'first_transaction',(select jsonb_build_object('id',f.id,'date',f.date,'description',f.effective_description,'amount_minor',f.amount_minor,'currency',f.currency,'account_name',f.account_name) from filtered f order by date asc,id asc limit 1),
 'last_transaction',(select jsonb_build_object('id',f.id,'date',f.date,'description',f.effective_description,'amount_minor',f.amount_minor,'currency',f.currency,'account_name',f.account_name) from filtered f order by date desc,id desc limit 1),
 'money_error',case when exists(select 1 from annotated where income_refund_conflict) then 'A refunded purchase category is planned as income. Correct the category or Budget plan to calculate monetary statistics.' end,
 'currencies',case when exists(select 1 from annotated where income_refund_conflict) then '[]'::jsonb else coalesce((select jsonb_agg(value order by currency) from summary_money),'[]'::jsonb) end), 'total',(select count(*) from filtered),'limit',_limit,'offset',_offset,'trash_total',(select count(*) from household_private.transactions where deleted_at is not null),'rows',
  coalesce((select jsonb_agg(row_data order by position) from ordered where position>_offset and position<=_offset+_limit),'[]'::jsonb)) into result;
 return result;
end $function$;

create function household_private.admin_transfer_logs(operation text,payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();actor_role text:=household_private.member_role();stream text;off integer;lim integer;result jsonb;
begin
 if operation<>'admin_get_transfer_logs' then raise exception using errcode='22023',message='Unknown administration operation';end if;
 perform household_private.planning_check(payload,array['stream','offset','limit']);stream:=household_private.planning_text(payload,'stream',1,10,'imports');off:=household_private.planning_int(payload,'offset',0,1000000,0);lim:=household_private.planning_int(payload,'limit',1,50,25);
 if stream not in ('imports','exports') then raise exception using errcode='22023',message='Choose imports or exports';end if;
 if stream='exports' then
  with events as materialized(select id::text,id as sequence,action,created_at,target_id from household_private.audit_events where action in ('export_transactions','export_csv','export_tax_documents')),page as(select * from events order by sequence desc limit lim offset off)
  select jsonb_build_object('stream',stream,'offset',off,'total',(select count(*) from events),'rows',coalesce((select jsonb_agg(to_jsonb(e)-'sequence' order by sequence desc) from page e),'[]'::jsonb),'downloads_tracked',false) into result;return result;
 end if;
 with events as materialized(
  select b.id,'csv'::text source,a.name account_name,b.created_at,b.committed_at,case when b.committed_at is null then 'staged' else 'imported' end status,
   b.selected_count,(select count(*) from household_private.staged_rows r where r.batch_id=b.id) expected_count,
   (select count(*) from household_private.transactions t where t.batch_id=b.id) inserted_count,
   case when b.committed_at is not null then greatest(coalesce(b.selected_count,0)-(select count(*) from household_private.transactions t where t.batch_id=b.id),0) end skipped_count,
   (select count(*) from household_private.staged_rows r where r.batch_id=b.id and r.error is not null) error_count,
   (select min(date) from household_private.staged_rows r where r.batch_id=b.id) period_start,(select max(date) from household_private.staged_rows r where r.batch_id=b.id) period_end,'[]'::jsonb coverage_notes,'browser'::text created_via
  from household_private.import_batches b join household_private.accounts a on a.id=b.account_id
  union all
  select s.id,s.source,s.payload->'account'->>'name',s.created_at,s.committed_at,case when s.committed_at is null then 'staged' else 'imported' end,null::integer,(s.payload->>'expected_count')::bigint,s.inserted_count::bigint,s.skipped_count::bigint,0::bigint,s.period_start,s.period_end,coalesce(s.payload->'coverage_notes','[]'::jsonb),s.created_via from household_private.source_snapshots s
 ),page as(select * from events order by created_at desc,id desc limit lim offset off)
 select jsonb_build_object('stream',stream,'offset',off,'total',(select count(*) from events),'rows',coalesce((select jsonb_agg(to_jsonb(e) order by created_at desc,id desc) from page e),'[]'::jsonb)) into result;return result;
end $$;
revoke all on function household_private.admin_transfer_logs(text,jsonb) from public,anon,authenticated;grant execute on function household_private.admin_transfer_logs(text,jsonb) to authenticated;
create function public.household_admin_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select household_private.admin_transfer_logs(operation,payload)$$;
revoke all on function public.household_admin_v1(text,jsonb) from public,anon,authenticated;grant execute on function public.household_admin_v1(text,jsonb) to authenticated;
notify pgrst,'reload schema';
