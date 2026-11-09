-- Broader source account kinds and insert-only note hydration; existing ledger edits remain untouched.
-- Supporting source catalogs are private archives, never executable automation configuration.
create table household_private.monarch_catalog_snapshots (
 id uuid primary key default gen_random_uuid(),
 captured_at timestamptz not null default now(),
 catalog_type text not null check (catalog_type in ('accounts','categories','tags','real_estate','recurring','rules','net_worth_history','investments','goals','budgets','coverage')),
 source_hash text not null,
 payload jsonb not null check (jsonb_typeof(payload)='object' and octet_length(payload::text)<=5000000),
 created_by uuid not null references auth.users(id),
 created_via text not null check (created_via='assistant'),
 unique(catalog_type,source_hash)
);
alter table household_private.monarch_catalog_snapshots enable row level security;
revoke all on household_private.monarch_catalog_snapshots from public,anon,authenticated;
create or replace function household_private.monarch_stage(payload jsonb,actor uuid,origin text) returns uuid
language plpgsql security definer set search_path='' set datestyle='ISO, YMD' as $$
declare item jsonb;first_day date;last_day date;ident uuid;normalized jsonb;fingerprint text;account jsonb:=payload->'account';row_count integer;
begin
 if not exists(select 1 from household_private.memberships where user_id=actor and status='approved' and role='owner') then
  raise exception using errcode='42501',message='Owner required for source imports';end if;
 if jsonb_typeof(payload) is distinct from 'object' or jsonb_typeof(account) is distinct from 'object'
  or jsonb_typeof(payload->'transactions') is distinct from 'array' or octet_length(payload::text)>5000000 then
  raise exception using errcode='22023',message='Invalid snapshot payload';end if;
 row_count:=jsonb_array_length(payload->'transactions');
 if row_count not between 1 and 5000 or coalesce((payload->>'expected_count')::integer,-1)<>row_count then
  raise exception using errcode='22023',message='Snapshot count does not match expected source count';end if;
 if coalesce(account->>'external_id','') !~ '^[0-9A-Za-z_-]{1,100}$' or length(btrim(coalesce(account->>'name',''))) not between 1 and 120
  or coalesce(account->>'currency','') !~ '^[A-Z]{3}$' or coalesce(account->>'kind','') not in ('checking','savings','credit','mortgage','loan','investment','asset','other') then
  raise exception using errcode='22023',message='Invalid source account';end if;
 if coalesce(payload->>'period_start','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(payload->>'period_end','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
  raise exception using errcode='22023',message='Invalid source period';end if;
 first_day:=(payload->>'period_start')::date;last_day:=(payload->>'period_end')::date;
 if last_day<first_day or last_day-first_day>366 then raise exception using errcode='22023',message='Invalid source period';end if;
 if row_count<>(select count(distinct value->>'external_id') from jsonb_array_elements(payload->'transactions')) then
  raise exception using errcode='22023',message='Repeated source transaction IDs';end if;
 for item in select value from jsonb_array_elements(payload->'transactions') loop
  if jsonb_typeof(item) is distinct from 'object' or coalesce(item->>'external_id','') !~ '^[0-9A-Za-z_-]{1,100}$'
   or item->>'account_external_id' is distinct from account->>'external_id' or item->'pending' is distinct from 'false'::jsonb
   or coalesce(item->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
   raise exception using errcode='22023',message='Transaction outside source account or not posted';end if;
  if (item->>'date')::date not between first_day and last_day or length(btrim(coalesce(item->>'description',''))) not between 1 and 500
   or coalesce(item->>'amount_minor','') !~ '^-?[0-9]{1,12}$' or abs((item->>'amount_minor')::bigint)>100000000000
   or length(coalesce(item->>'category',''))>120 or jsonb_typeof(item->'source_data') is distinct from 'object' then
   raise exception using errcode='22023',message='Invalid source transaction';end if;
 end loop;
 select jsonb_set(payload,'{transactions}',jsonb_agg(value order by value->>'external_id')) into normalized from jsonb_array_elements(payload->'transactions');
 fingerprint:=encode(sha256(convert_to(normalized::text,'UTF8')),'hex');
 insert into household_private.source_snapshots(source,external_account_id,period_start,period_end,source_hash,payload,created_by,created_via)
  values('monarch',account->>'external_id',first_day,last_day,fingerprint,normalized,actor,origin)
  on conflict(source,external_account_id,period_start,period_end,source_hash) do update set source_hash=excluded.source_hash returning id into ident;
 return ident;
end $$;

create or replace function household_private.monarch_commit(snapshot_id uuid,actor uuid) returns jsonb
language plpgsql security definer set search_path='' set datestyle='ISO, YMD' as $$
declare snap household_private.source_snapshots;account_uuid uuid;category_uuid uuid;item jsonb;fp text;inserted integer:=0;skipped integer:=0;account jsonb;
begin
 if not exists(select 1 from household_private.memberships where user_id=actor and status='approved' and role='owner') then
  raise exception using errcode='42501',message='Owner required for source imports';end if;
 select * into snap from household_private.source_snapshots where id=snapshot_id for update;
 if snap.id is null then raise exception using errcode='P0002',message='Snapshot not found';end if;
 if snap.committed_at is not null then return jsonb_build_object('inserted',0,'skipped',jsonb_array_length(snap.payload->'transactions'),'already_committed',true);end if;
 account:=snap.payload->'account';
 insert into household_private.accounts(name,kind,currency,source,external_id,source_metadata)
  values(account->>'name',account->>'kind',account->>'currency','monarch',account->>'external_id',coalesce(account->'metadata','{}'::jsonb))
  on conflict(source,external_id) do update set external_id=excluded.external_id returning id into account_uuid;
 -- The account upsert locks its row, serializing overlapping snapshots for this account.
 for item in select value from jsonb_array_elements(snap.payload->'transactions') loop
  if exists(select 1 from household_private.transactions t where t.source='monarch' and t.external_id=item->>'external_id') then
   if not exists(select 1 from household_private.transactions t where t.source='monarch' and t.external_id=item->>'external_id'
    and t.account_id=account_uuid and t.date=(item->>'date')::date and t.amount_minor=(item->>'amount_minor')::bigint and t.description=item->>'description') then
    raise exception using errcode='40001',message='Previously imported transaction changed; review before replacing';end if;
   skipped:=skipped+1;continue;
  end if;
  fp:=encode(sha256(convert_to(jsonb_build_array((item->>'date')::date,lower(regexp_replace(btrim(item->>'description'),'\s+',' ','g')),(item->>'amount_minor')::bigint)::text,'UTF8')),'hex');
  if exists(select 1 from household_private.transactions t where t.account_id=account_uuid and t.source is null and t.fingerprint=fp) then
   raise exception using errcode='40001',message='Possible overlap with CSV import; review before importing';end if;
  category_uuid:=null;
  if length(btrim(coalesce(item->>'category','')))>0 then
   insert into household_private.categories(name) values(btrim(item->>'category')) on conflict(name) do update set name=excluded.name returning id into category_uuid;
  end if;
  insert into household_private.transactions(account_id,category_id,date,description,amount_minor,fingerprint,source,external_id,source_data,notes)
   values(account_uuid,category_uuid,(item->>'date')::date,item->>'description',(item->>'amount_minor')::bigint,fp,'monarch',item->>'external_id',item->'source_data',coalesce(item->'source_data'->>'notes',''));
  inserted:=inserted+1;
 end loop;
 update household_private.source_snapshots set committed_at=now(),inserted_count=inserted,skipped_count=skipped where id=snapshot_id;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,'commit_monarch_snapshot_'||snap.created_via,snapshot_id);
 return jsonb_build_object('inserted',inserted,'skipped',skipped,'account_id',account_uuid);
end $$;

revoke all on function household_private.monarch_stage(jsonb,uuid,text),household_private.monarch_commit(uuid,uuid) from public,anon,authenticated;
