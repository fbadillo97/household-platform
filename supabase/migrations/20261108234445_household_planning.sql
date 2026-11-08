-- Household planning foundation. No household data is seeded or backfilled.
create function household_private.planning_check(p jsonb,keys text[]) returns void language plpgsql set search_path='' as $$
begin
 if p is null or jsonb_typeof(p)<>'object' or octet_length(p::text)>1000000 or exists(select 1 from jsonb_object_keys(p) k where not(k=any(keys))) then raise exception using errcode='22023',message='Invalid planning request fields';end if;
end $$;
create function household_private.planning_int(p jsonb,k text,lo bigint,hi bigint,fallback bigint default null) returns bigint language plpgsql set search_path='' as $$
declare v numeric;
begin
 if not p?k or p->k='null'::jsonb then return fallback;end if;
 if jsonb_typeof(p->k)<>'number' or p->>k !~ '^-?[0-9]+$' then raise exception using errcode='22023',message='Use an integer for '||k;end if;
 v:=(p->>k)::numeric;if v<lo or v>hi then raise exception using errcode='22023',message='Value outside supported range: '||k;end if;return v::bigint;
end $$;
create function household_private.planning_text(p jsonb,k text,lo integer,hi integer,fallback text default '') returns text language plpgsql set search_path='' as $$
declare v text;
begin
 if not p?k or p->k='null'::jsonb then v:=fallback;
 elsif jsonb_typeof(p->k)<>'string' then raise exception using errcode='22023',message='Use text for '||k;
 else v:=btrim(p->>k);end if;
 if v is null or length(v)<lo or length(v)>hi then raise exception using errcode='22023',message='Check '||k||' length';end if;return v;
end $$;
create function household_private.planning_bool(p jsonb,k text,fallback boolean default false) returns boolean language plpgsql set search_path='' as $$
begin
 if not p?k then return fallback;end if;if jsonb_typeof(p->k) is distinct from 'boolean' then raise exception using errcode='22023',message='Use true or false for '||k;end if;return (p->>k)::boolean;
end $$;
create function household_private.planning_date(p jsonb,k text) returns date language plpgsql set search_path='' as $$
begin
 if not p?k or p->k='null'::jsonb then return null;end if;
 if jsonb_typeof(p->k)<>'string' or p->>k !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception using errcode='22023',message='Use a valid date for '||k;end if;
 return (p->>k)::date;
exception when datetime_field_overflow or invalid_datetime_format then raise exception using errcode='22023',message='Use a valid date for '||k;
end $$;
create function household_private.planning_safe(v numeric) returns bigint language plpgsql immutable set search_path='' as $$
begin if v is null or v<>trunc(v) or abs(v)>9007199254740991 then raise exception using errcode='22023',message='Money total exceeds the supported range';end if;return v::bigint;end $$;
create function household_private.planning_today() returns date language sql stable set search_path='' as $$ select (now() at time zone 'America/Toronto')::date $$;
create function household_private.planning_month(p jsonb,k text) returns date language plpgsql set search_path='' as $$
declare value text:=household_private.planning_text(p,k,7,7);
begin if value !~ '^(19[0-9]{2}|20[0-9]{2}|2100)-(0[1-9]|1[0-2])$' then raise exception using errcode='22023',message='Choose a supported month';end if;return (value||'-01')::date;end $$;
create view household_private.planning_transactions with(security_invoker=true) as
 select t.id,t.revision,t.date,t.amount_minor,t.category_id,t.flow_type,t.deleted_at,
 coalesce(t.account_override_id,t.account_id) account_id,a.currency,a.name account_name,
 coalesce(t.description_override,t.description) description,c.name category_name,
 coalesce(t.tags_override::text,(t.source_data->'tags')::text,'') tags_text
 from household_private.transactions t join household_private.accounts a on a.id=coalesce(t.account_override_id,t.account_id)
 left join household_private.categories c on c.id=t.category_id;
revoke all on household_private.planning_transactions from public,anon,authenticated;

create table household_private.tax_people (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 100),
 created_at timestamptz not null default now()
);
create unique index tax_people_name_idx on household_private.tax_people(lower(btrim(name)));
create table household_private.tax_returns (
 id uuid primary key default gen_random_uuid(),
 year integer not null check(year between 1900 and 2100),
 person_id uuid not null references household_private.tax_people(id),
 workstream text not null check(workstream in ('canada','us','fbar')),
 status text not null default 'collecting' check(status in ('collecting','ready','filed')),
 due_date date,notes text not null default '' check(length(notes)<=10000),
 revision integer not null default 1 check(revision>0),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(year,person_id,workstream)
);
create index tax_returns_person_idx on household_private.tax_returns(person_id);
create table household_private.tax_items (
 id uuid primary key default gen_random_uuid(),return_id uuid not null references household_private.tax_returns(id),
 title text not null check(length(btrim(title)) between 1 and 200),
 status text not null default 'missing' check(status in ('missing','in_progress','collected','reviewed','not_applicable')),
 due_date date,notes text not null default '' check(length(notes)<=10000),
 archived_at timestamptz,revision integer not null default 1 check(revision>0),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index tax_items_return_idx on household_private.tax_items(return_id);
create table household_private.tax_expenses (
 id uuid primary key default gen_random_uuid(),return_id uuid not null references household_private.tax_returns(id),
 transaction_id uuid not null references household_private.transactions(id),
 purpose text not null check(length(btrim(purpose)) between 1 and 200),
 receipt_required boolean not null default true,reviewed boolean not null default false,
 notes text not null default '' check(length(notes)<=10000),archived_at timestamptz,
 revision integer not null default 1 check(revision>0),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(return_id,transaction_id)
);
create index tax_expenses_transaction_idx on household_private.tax_expenses(transaction_id);
create table household_private.tax_documents (
 id uuid primary key default gen_random_uuid(),year integer not null check(year between 1900 and 2100),
 object_path text not null unique,filename text not null check(length(filename) between 1 and 180),
 mime_type text not null check(mime_type in ('application/pdf','image/jpeg','image/png','image/webp')),
 byte_size bigint not null check(byte_size between 1 and 10485760),sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
 state text not null default 'pending' check(state in ('pending','ready','removed')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 removed_at timestamptz,revision integer not null default 1 check(revision>0)
);
create unique index tax_documents_hash_idx on household_private.tax_documents(year,sha256) where removed_at is null;
create index tax_documents_creator_idx on household_private.tax_documents(created_by);
create table household_private.tax_document_links (
 document_id uuid not null references household_private.tax_documents(id),
 item_id uuid references household_private.tax_items(id),expense_id uuid references household_private.tax_expenses(id),
 check(num_nonnulls(item_id,expense_id)=1),
 created_at timestamptz not null default now()
);
create unique index tax_document_item_idx on household_private.tax_document_links(document_id,item_id) where item_id is not null;
create unique index tax_document_expense_idx on household_private.tax_document_links(document_id,expense_id) where expense_id is not null;
create index tax_links_item_idx on household_private.tax_document_links(item_id);
create index tax_links_expense_idx on household_private.tax_document_links(expense_id);
-- All browser access must go through the approved passkey-checked RPC. No table grants.
alter table household_private.tax_people enable row level security;
alter table household_private.tax_returns enable row level security;
alter table household_private.tax_items enable row level security;
alter table household_private.tax_expenses enable row level security;
alter table household_private.tax_documents enable row level security;
alter table household_private.tax_document_links enable row level security;
revoke all on household_private.tax_people,household_private.tax_returns,household_private.tax_items,
 household_private.tax_expenses,household_private.tax_documents,household_private.tax_document_links from public,anon,authenticated;
-- Never expose a document bucket publicly or authorize using user_metadata.

alter table household_private.tax_items add column copied_from_id uuid references household_private.tax_items(id);
create unique index tax_copy_once_idx on household_private.tax_items(return_id,copied_from_id) where copied_from_id is not null;
create index tax_copied_from_idx on household_private.tax_items(copied_from_id);
alter table household_private.tax_document_links add column unlinked_at timestamptz;
create function household_private.tax_workspace(y integer) returns jsonb language plpgsql stable set search_path='' as $$
declare result jsonb;
begin
 if (select count(*) from household_private.tax_returns where year=y)>5000
 or (select count(*) from household_private.tax_items i join household_private.tax_returns r on r.id=i.return_id where r.year=y)>5000
 or (select count(*) from household_private.tax_expenses e join household_private.tax_returns r on r.id=e.return_id where r.year=y)>5000
 or (select count(*) from household_private.tax_documents where year=y)>5000
 or (select count(*) from household_private.tax_people)>100 then raise exception using errcode='22023',message='Tax workspace is too large';end if;
 select jsonb_build_object('year',y,
 'people',coalesce((select jsonb_agg(to_jsonb(p) order by p.name,p.id) from household_private.tax_people p),'[]'::jsonb),
 'returns',coalesce((select jsonb_agg(to_jsonb(r) order by r.person_id,r.workstream) from household_private.tax_returns r where r.year=y),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.title,i.id) from household_private.tax_items i join household_private.tax_returns r on r.id=i.return_id where r.year=y),'[]'::jsonb),
 'expenses',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('description',t.description,'date',t.date,'amount_minor',t.amount_minor,'currency',t.currency,'account_name',t.account_name,'tags_text',t.tags_text,'transaction_deleted_at',t.deleted_at,'receipt_count',(select count(*) from household_private.receipts s where s.transaction_id=e.transaction_id and s.state='ready' and s.removed_at is null)) order by t.date desc,e.id) from household_private.tax_expenses e join household_private.tax_returns r on r.id=e.return_id join household_private.planning_transactions t on t.id=e.transaction_id where r.year=y),'[]'::jsonb),
 'documents',coalesce((select jsonb_agg(to_jsonb(d)-'created_by' order by d.created_at,d.id) from household_private.tax_documents d where d.year=y and d.removed_at is null),'[]'::jsonb),
 'links',coalesce((select jsonb_agg(jsonb_build_object('document_id',l.document_id,'target_kind',case when l.item_id is not null then 'item' else 'expense' end,'target_id',coalesce(l.item_id,l.expense_id))) from household_private.tax_document_links l join household_private.tax_documents d on d.id=l.document_id where d.year=y and d.removed_at is null and l.unlinked_at is null),'[]'::jsonb)) into result;
 if octet_length(result::text)>8000000 then raise exception using errcode='22023',message='Tax workspace is too large';end if;return result;
end $$;
create function household_private.tax_target(kind text,ident uuid,require_active boolean default true) returns integer language plpgsql set search_path='' as $$
declare y integer;archived timestamptz;
begin
 if kind='item' then select r.year,i.archived_at into y,archived from household_private.tax_items i join household_private.tax_returns r on r.id=i.return_id where i.id=ident for update of i;
 elsif kind='expense' then select r.year,e.archived_at into y,archived from household_private.tax_expenses e join household_private.tax_returns r on r.id=e.return_id where e.id=ident for update of e;
 else raise exception using errcode='22023',message='Unknown tax document target';end if;
 if y is null then raise exception using errcode='P0002',message='Tax record not found';end if;
 if require_active and archived is not null then raise exception using errcode='40001',message='Restore this tax record before editing';end if;return y;
end $$;
create function household_private.tax_document_action(op text,p jsonb,actor uuid) returns jsonb language plpgsql set search_path='' as $$
declare d household_private.tax_documents;kind text;ident uuid;y integer;meta jsonb;filename text;mime text;hash text;bytes bigint;
begin
 if op='tax_finish_document' then
  perform household_private.planning_check(p,array['id','revision']);select * into d from household_private.tax_documents where id=(p->>'id')::uuid for update;
  if d.id is null or d.removed_at is not null then raise exception using errcode='P0002',message='Tax document not found';end if;
  if d.revision is distinct from household_private.planning_int(p,'revision',1,2147483647) then raise exception using errcode='40001',message='Document changed; reload';end if;
  if d.created_by<>actor then raise exception using errcode='42501',message='Only the uploader can finish this upload';end if;
  if d.state='ready' then return to_jsonb(d)-'created_by';end if;
  select o.metadata into meta from storage.objects o where o.bucket_id='household-tax-documents' and o.name=d.object_path;
  if meta is null or coalesce((meta->>'size')::bigint,-1)<>d.byte_size or meta->>'mimetype' is distinct from d.mime_type then raise exception using errcode='22023',message='Uploaded document is missing or does not match its prepared type/size';end if;
  update household_private.tax_documents set state='ready',revision=revision+1 where id=d.id returning * into d;
 else
  if op='tax_prepare_document' then perform household_private.planning_check(p,array['year','target_kind','target_id','filename','mime_type','byte_size','sha256']);
  else perform household_private.planning_check(p,array['target_kind','target_id','document_id']);end if;
  kind:=household_private.planning_text(p,'target_kind',1,10);ident:=(p->>'target_id')::uuid;y:=household_private.tax_target(kind,ident,op<>'tax_unlink_document');
  -- Serialize preparations by year, then target. Same-file retry cannot race a duplicate insert.
  if op='tax_prepare_document' then
   if y is distinct from household_private.planning_int(p,'year',1900,2100) then raise exception using errcode='22023',message='Document and tax record must have the same year';end if;
   perform pg_advisory_xact_lock(79123,y);
   filename:=household_private.planning_text(p,'filename',1,180);mime:=household_private.planning_text(p,'mime_type',1,100);hash:=household_private.planning_text(p,'sha256',64,64);bytes:=household_private.planning_int(p,'byte_size',1,10485760);
   if filename ~ '[[:cntrl:]]' or strpos(filename,'/')>0 or strpos(filename,chr(92))>0 or mime not in ('application/pdf','image/jpeg','image/png','image/webp') or hash !~ '^[0-9a-f]{64}$' or bytes is null then raise exception using errcode='22023',message='Use a PDF, JPEG, PNG or WebP document up to 10 MB';end if;
   select * into d from household_private.tax_documents where year=y and sha256=hash and removed_at is null for update;
   if d.id is null then
    if (select count(*) from household_private.tax_documents where year=y)>=5000 then raise exception using errcode='22023',message='Document limit reached for this year';end if;
    ident:=gen_random_uuid();insert into household_private.tax_documents(id,year,object_path,filename,mime_type,byte_size,sha256,created_by) values(ident,y,y::text||'/'||ident::text,filename,mime,bytes,hash,actor) returning * into d;
   elsif d.state='pending' and d.created_by<>actor then raise exception using errcode='40001',message='Another member is uploading this document';end if;
   ident:=(p->>'target_id')::uuid;
  else select * into d from household_private.tax_documents where id=(p->>'document_id')::uuid and removed_at is null for update;end if;
  if d.id is null or d.year<>y then raise exception using errcode='22023',message='Document must belong to the same tax year';end if;
  if op='tax_unlink_document' then update household_private.tax_document_links set unlinked_at=now() where document_id=d.id and ((kind='item' and item_id=ident) or (kind='expense' and expense_id=ident));
  else
   if op='tax_link_document' and d.state<>'ready' then raise exception using errcode='22023',message='Finish uploading before reusing this document';end if;
   update household_private.tax_document_links set unlinked_at=null where document_id=d.id and ((kind='item' and item_id=ident) or (kind='expense' and expense_id=ident));
   insert into household_private.tax_document_links(document_id,item_id,expense_id) values(d.id,case when kind='item' then ident end,case when kind='expense' then ident end) on conflict do nothing;
  end if;
 end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,op,d.id);
 return (to_jsonb(d)-'created_by')||jsonb_build_object('already_exists',d.state='ready');
end $$;
create function household_private.tax_dispatch(operation text,payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_actor_role text:=household_private.member_role();p jsonb:=payload;y integer;ident uuid;person uuid;ret household_private.tax_returns;item household_private.tax_items;expense household_private.tax_expenses;stream text;srcyear integer;_name text;_revision integer;entry jsonb;tx household_private.transactions;created integer:=0;skipped integer:=0;q text;off integer;lim integer;result jsonb;purpose text;
begin
 if operation='tax_get_workspace' then perform household_private.planning_check(p,array['year']);y:=household_private.planning_int(p,'year',1900,2100);if y is null then raise exception using errcode='22023',message='Choose a tax year';end if;return household_private.tax_workspace(y);end if;
 if operation='tax_find_transactions' then
  perform household_private.planning_check(p,array['year','query','offset','limit']);y:=household_private.planning_int(p,'year',1900,2100);q:=household_private.planning_text(p,'query',0,500);off:=household_private.planning_int(p,'offset',0,1000000,0);lim:=household_private.planning_int(p,'limit',1,50,50);
  if y is null then raise exception using errcode='22023',message='Choose a tax year';end if;
  with f as materialized (select * from household_private.planning_transactions t where t.deleted_at is null and t.date>=make_date(y,1,1) and t.date<make_date(y+1,1,1) and strpos(lower(concat_ws(' ',t.description,t.account_name,t.category_name,t.tags_text)),lower(q))>0),page as(select * from f order by date desc,id limit lim offset off)
  select jsonb_build_object('total',(select count(*) from f),'rows',coalesce((select jsonb_agg(to_jsonb(t) order by date desc,id) from page t),'[]'::jsonb)) into result;return result;
 end if;
 if operation in ('tax_prepare_document','tax_finish_document','tax_link_document','tax_unlink_document') then return household_private.tax_document_action(operation,p,actor);end if;
 if operation='tax_create_workspace' then
  perform household_private.planning_check(p,array['year','person_id','name','workstreams','copy_from_year']);y:=household_private.planning_int(p,'year',1900,2100);srcyear:=household_private.planning_int(p,'copy_from_year',1900,2100);if y is null or (srcyear is not null and srcyear>=y) then raise exception using errcode='22023',message='Choose a tax year and an earlier copy source';end if;
  if jsonb_typeof(p->'workstreams') is distinct from 'array' or jsonb_array_length(p->'workstreams') not between 1 and 3 or exists(select 1 from jsonb_array_elements(p->'workstreams') s where jsonb_typeof(s)<>'string' or s#>>'{}' not in ('canada','us','fbar')) or (select count(distinct s) from jsonb_array_elements_text(p->'workstreams') s)<>jsonb_array_length(p->'workstreams') then raise exception using errcode='22023',message='Choose one or more distinct workstreams';end if;
  perform pg_advisory_xact_lock(79122,0);person:=nullif(p->>'person_id','')::uuid;
  if person is null then _name:=household_private.planning_text(p,'name',1,100);select id into person from household_private.tax_people where lower(btrim(tax_people.name))=lower(_name);
   if person is null then if (select count(*) from household_private.tax_people)>=100 then raise exception using errcode='22023',message='Tax person limit reached';end if;insert into household_private.tax_people(name) values(_name) returning id into person;end if;
  elsif not exists(select 1 from household_private.tax_people where id=person) then raise exception using errcode='P0002',message='Tax person not found';end if;
  for stream in select jsonb_array_elements_text(p->'workstreams') loop
   insert into household_private.tax_returns(year,person_id,workstream) values(y,person,stream) on conflict(year,person_id,workstream) do nothing;
   select * into ret from household_private.tax_returns where year=y and person_id=person and workstream=stream for update;
   if srcyear is not null then
    insert into household_private.tax_items(return_id,title,copied_from_id)
    select ret.id,i.title,i.id from household_private.tax_items i join household_private.tax_returns r on r.id=i.return_id where r.year=srcyear and r.person_id=person and r.workstream=stream and i.archived_at is null on conflict do nothing;
   end if;
  end loop;
  insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,person);return household_private.tax_workspace(y);
 end if;
 if operation='tax_flag_expenses' then
  perform household_private.planning_check(p,array['year','return_id','purpose','receipt_required','items']);y:=household_private.planning_int(p,'year',1900,2100);purpose:=household_private.planning_text(p,'purpose',1,200);perform household_private.planning_bool(p,'receipt_required',true);
  select * into ret from household_private.tax_returns where id=(p->>'return_id')::uuid for update;
  if ret.id is null or ret.year is distinct from y then raise exception using errcode='22023',message='Choose a workstream in this year';end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') not between 1 and 50 or (select count(distinct e->>'id') from jsonb_array_elements(p->'items') e)<>jsonb_array_length(p->'items') then raise exception using errcode='22023',message='Select 1–50 distinct transactions';end if;
  for entry in select e from jsonb_array_elements(p->'items') e order by (e->>'id')::uuid loop
   perform household_private.planning_check(entry,array['id','revision']);select * into tx from household_private.transactions where id=(entry->>'id')::uuid for update;
   if tx.id is null or tx.deleted_at is not null or tx.revision is distinct from household_private.planning_int(entry,'revision',1,2147483647) then raise exception using errcode='40001',message='A selected transaction changed; reload. Nothing was flagged';end if;
  end loop;
  for entry in select e from jsonb_array_elements(p->'items') e loop
   insert into household_private.tax_expenses(return_id,transaction_id,purpose,receipt_required) values(ret.id,(entry->>'id')::uuid,purpose,household_private.planning_bool(p,'receipt_required',true)) on conflict(return_id,transaction_id) do nothing returning id into ident;
   if ident is null then skipped:=skipped+1;else created:=created+1;insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);end if;
  end loop;return jsonb_build_object('created_count',created,'skipped_count',skipped);
 end if;
 if operation in ('tax_archive_item','tax_archive_expense') then
  perform household_private.planning_check(p,array['id','revision','archived']);ident:=(p->>'id')::uuid;_revision:=household_private.planning_int(p,'revision',1,2147483647);perform household_private.planning_bool(p,'archived');
  if operation='tax_archive_item' then select * into item from household_private.tax_items where id=ident for update;
   if item.id is null then raise exception using errcode='P0002',message='Checklist item not found';end if;if item.revision is distinct from _revision then raise exception using errcode='40001',message='Checklist item changed; reload';end if;
   update household_private.tax_items set archived_at=case when (p->>'archived')::boolean then now() end,revision=tax_items.revision+1,updated_at=now() where id=ident;
  else select * into expense from household_private.tax_expenses where id=ident for update;
   if expense.id is null then raise exception using errcode='P0002',message='Tax expense not found';end if;if expense.revision is distinct from _revision then raise exception using errcode='40001',message='Tax expense changed; reload';end if;
   update household_private.tax_expenses set archived_at=case when (p->>'archived')::boolean then now() end,revision=tax_expenses.revision+1,updated_at=now() where id=ident;
  end if;
 elsif operation in ('tax_save_item','tax_save_expense','tax_save_return') then
  if operation='tax_save_item' then perform household_private.planning_check(p,array['id','revision','year','return_id','title','status','due_date','notes']);
  elsif operation='tax_save_expense' then perform household_private.planning_check(p,array['id','revision','year','return_id','purpose','notes','receipt_required','reviewed']);
  else perform household_private.planning_check(p,array['id','revision','year','status','due_date','notes']);end if;
  y:=household_private.planning_int(p,'year',1900,2100);ident:=(p->>'id')::uuid;_revision:=household_private.planning_int(p,'revision',1,2147483647);
  if y is null then raise exception using errcode='22023',message='Choose a tax year';end if;
  if operation='tax_save_return' then
   select * into ret from household_private.tax_returns where id=ident for update;if ret.id is null or ret.year<>y then raise exception using errcode='P0002',message='Tax workstream not found';end if;
   if ret.revision is distinct from _revision then raise exception using errcode='40001',message='Filing record changed; reload';end if;
   if p->>'status' not in ('collecting','ready','filed') or p->>'status' is null then raise exception using errcode='22023',message='Choose a filing status';end if;
   update household_private.tax_returns set status=p->>'status',due_date=household_private.planning_date(p,'due_date'),notes=household_private.planning_text(p,'notes',0,10000),revision=tax_returns.revision+1,updated_at=now() where id=ident;
  else
   select * into ret from household_private.tax_returns where id=(p->>'return_id')::uuid for update;if ret.id is null or ret.year<>y then raise exception using errcode='22023',message='Choose a workstream in this year';end if;
   if operation='tax_save_item' then
    if p->>'status' not in ('missing','in_progress','collected','reviewed','not_applicable') or p->>'status' is null then raise exception using errcode='22023',message='Choose a checklist status';end if;
    _name:=household_private.planning_text(p,'title',1,200);
    if ident is null then insert into household_private.tax_items(return_id,title,status,due_date,notes) values(ret.id,_name,p->>'status',household_private.planning_date(p,'due_date'),household_private.planning_text(p,'notes',0,10000)) returning id into ident;
    else
     select * into item from household_private.tax_items where id=ident for update;
     if item.id is null then raise exception using errcode='P0002',message='Checklist item not found';end if;
     if item.revision is distinct from _revision or item.archived_at is not null then raise exception using errcode='40001',message='Checklist item changed or is archived; reload';end if;
     if (select year from household_private.tax_returns where id=item.return_id)<>y then raise exception using errcode='22023',message='Cannot move evidence to another tax year';end if;
     update household_private.tax_items set return_id=ret.id,title=_name,status=p->>'status',due_date=household_private.planning_date(p,'due_date'),notes=household_private.planning_text(p,'notes',0,10000),revision=tax_items.revision+1,updated_at=now() where id=ident;
    end if;
   else
    select * into expense from household_private.tax_expenses where id=ident for update;
    if expense.id is null then raise exception using errcode='P0002',message='Tax expense not found';end if;
    if expense.revision is distinct from _revision or expense.archived_at is not null then raise exception using errcode='40001',message='Tax expense changed or is archived; reload';end if;
    if (select year from household_private.tax_returns where id=expense.return_id)<>y then raise exception using errcode='22023',message='Cannot move evidence to another tax year';end if;
    update household_private.tax_expenses set return_id=ret.id,purpose=household_private.planning_text(p,'purpose',1,200),notes=household_private.planning_text(p,'notes',0,10000),receipt_required=household_private.planning_bool(p,'receipt_required',true),reviewed=household_private.planning_bool(p,'reviewed'),revision=tax_expenses.revision+1,updated_at=now() where id=ident;
   end if;
  end if;
 else raise exception using errcode='22023',message='Unknown tax operation';end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);return jsonb_build_object('id',ident);
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('household-tax-documents','household-tax-documents',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp']);
create function household_private.tax_document_permission(object_name text,action text) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid;d household_private.tax_documents;
begin
 actor:=household_private.identity_id();perform household_private.member_role();
 select * into d from household_private.tax_documents where object_path=object_name and removed_at is null;
 if d.id is null then return false;end if;
 if action='read' then return d.state='ready' or (d.state='pending' and d.created_by=actor);end if;
 return action='upload' and d.state='pending' and d.created_by=actor;
exception when insufficient_privilege then return false;
end $$;
create policy household_tax_documents_read on storage.objects for select to authenticated using(bucket_id='household-tax-documents' and household_private.tax_document_permission(name,'read'));
create policy household_tax_documents_upload on storage.objects for insert to authenticated with check(bucket_id='household-tax-documents' and household_private.tax_document_permission(name,'upload'));
create function public.household_tax_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select household_private.tax_dispatch(operation,payload)$$;

create table household_private.budget_settings (
 currency text primary key check(currency ~ '^[A-Z]{3}$'),
 refund_timing text not null check(refund_timing in ('received','purchase')),
 anchor_month date not null check(extract(day from anchor_month)=1),
 revision integer not null default 1 check(revision>0),
 updated_at timestamptz not null default now()
);
create table household_private.budget_months (
 id uuid primary key default gen_random_uuid(),
 month date not null check(extract(day from month)=1 and month between '1900-01-01' and '2100-12-01'),
 currency text not null references household_private.budget_settings(currency),
 revision integer not null default 1 check(revision>0),
 coverage_confirmed_at timestamptz,coverage_confirmed_by uuid references auth.users(id),
 coverage_account_scope text, -- normalized account-cohort fingerprint, verified at reporting time
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(month,currency)
);
create index budget_months_currency_idx on household_private.budget_months(currency);
create index budget_months_confirmer_idx on household_private.budget_months(coverage_confirmed_by);
create table household_private.budget_lines (
 month_id uuid not null references household_private.budget_months(id),
 category_id uuid not null references household_private.categories(id),
 role text not null check(role in ('expense','income')),
 planned_minor bigint not null check(planned_minor between 0 and 9007199254740991),
 rollover_mode text not null default 'reset' check(rollover_mode in ('reset','unused')),
 cap_minor bigint check(cap_minor between 0 and 9007199254740991),
 check(role='expense' or (rollover_mode='reset' and cap_minor is null)),
 check(rollover_mode<>'reset' or cap_minor is null),
 primary key(month_id,category_id)
);
create index budget_lines_category_idx on household_private.budget_lines(category_id);
create table household_private.budget_refund_links (
 id uuid primary key default gen_random_uuid(),
 purchase_id uuid not null references household_private.transactions(id),
 refund_id uuid not null references household_private.transactions(id),
 amount_minor bigint not null check(amount_minor between 1 and 9007199254740991),
 check(purchase_id<>refund_id),
 revision integer not null default 1 check(revision>0),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unlinked_at timestamptz,unlinked_by uuid references auth.users(id)
);
create unique index budget_refund_pair_idx on household_private.budget_refund_links(purchase_id,refund_id) where unlinked_at is null;
create index budget_refund_purchase_idx on household_private.budget_refund_links(purchase_id);
create index budget_refund_credit_idx on household_private.budget_refund_links(refund_id);
create index budget_refund_creator_idx on household_private.budget_refund_links(created_by);
create index budget_refund_unlinker_idx on household_private.budget_refund_links(unlinked_by);
create table household_private.budget_benchmark_preferences (
 singleton boolean primary key default true check(singleton),
 cohort_label text not null check(length(cohort_label) between 1 and 200),
 source_table text not null check(source_table='11-10-0223-01'),
 reference_year integer not null check(reference_year between 1900 and 2100),
 revision integer not null default 1 check(revision>0)
);
create table household_private.budget_benchmark_mappings (
 category_id uuid primary key references household_private.categories(id),
 source_table text not null check(source_table='11-10-0223-01'),
 reference_year integer not null check(reference_year between 1900 and 2100),
 expenditure_label text not null check(length(expenditure_label) between 1 and 300),
 comparable boolean not null default false,note text not null default '' check(length(note)<=1000),enabled boolean not null default true
);
create unique index budget_active_benchmark_series_idx on household_private.budget_benchmark_mappings(source_table,reference_year,expenditure_label) where enabled;
create table household_private.budget_comparison_profile (
 singleton boolean primary key default true check(singleton),
 adults smallint check(adults between 1 and 30),children smallint check(children between 0 and 30),
 province text not null default '' check(length(province)<=80),
 tenure text not null default '' check(tenure in ('','owner','renter')),
 income_quintile text not null default '' check(income_quintile in ('','Lowest quintile','Second quintile','Third quintile','Fourth quintile','Highest quintile')),
 revision integer not null default 1 check(revision>0)
);
alter table household_private.budget_settings enable row level security;
alter table household_private.budget_months enable row level security;
alter table household_private.budget_lines enable row level security;
alter table household_private.budget_refund_links enable row level security;
alter table household_private.budget_benchmark_preferences enable row level security;
alter table household_private.budget_benchmark_mappings enable row level security;
alter table household_private.budget_comparison_profile enable row level security;
revoke all on household_private.budget_settings,household_private.budget_months,
 household_private.budget_lines,household_private.budget_refund_links,
 household_private.budget_benchmark_preferences,household_private.budget_benchmark_mappings,
 household_private.budget_comparison_profile from public,anon,authenticated;
-- No seed household profile, budgets, mappings or refund links. The public StatCan
-- snapshot is separate from these private records. Do not expose arbitrary SQL/report APIs.

create view household_private.budget_refund_context with(security_invoker=true) as
 with links as (
  select l.*,sum(l.amount_minor::numeric) over(partition by l.purchase_id) purchase_total,sum(l.amount_minor::numeric) over(partition by l.refund_id) refund_total
  from household_private.budget_refund_links l where l.unlinked_at is null
 )
 select l.id,l.revision,l.purchase_id,l.refund_id,l.amount_minor,p.category_id,
 p.date purchase_date,r.date refund_date,p.description purchase_description,r.description refund_description,
 p.currency purchase_currency,r.currency refund_currency,
 (p.deleted_at is null and r.deleted_at is null and p.flow_type='regular' and r.flow_type='regular' and p.currency=r.currency and p.amount_minor<0 and r.amount_minor>0 and l.purchase_total<=-p.amount_minor::numeric and l.refund_total<=r.amount_minor::numeric) valid
 from links l join household_private.planning_transactions p on p.id=l.purchase_id join household_private.planning_transactions r on r.id=l.refund_id;
revoke all on household_private.budget_refund_context from public,anon,authenticated;
create function household_private.budget_events(code text,timing text)
 returns table(event_month date,category_id uuid,value numeric,kind text,transaction_id uuid,peer_id uuid)
 language sql stable set search_path='' as $$
 with tx as materialized(select * from household_private.planning_transactions where currency=code and deleted_at is null and flow_type='regular'),
 links as materialized(select * from household_private.budget_refund_context where valid and purchase_currency=code)
 select date_trunc('month',t.date)::date,t.category_id,-t.amount_minor::numeric,'outflow',t.id,null::uuid from tx t where t.amount_minor<0
 union all
 select date_trunc('month',case when timing='purchase' then l.purchase_date else l.refund_date end)::date,l.category_id,-l.amount_minor::numeric,'refund',l.refund_id,l.purchase_id from links l
 union all
 select date_trunc('month',t.date)::date,t.category_id,t.amount_minor::numeric-coalesce((select sum(l.amount_minor) from links l where l.refund_id=t.id),0),
 case when exists(select 1 from household_private.budget_refund_links l where l.refund_id=t.id and l.unlinked_at is null) then 'refund_remainder' else 'credit' end,t.id,null::uuid from tx t where t.amount_minor>0
$$;
create function household_private.budget_actuals(m date,code text,plan_lines jsonb,timing text) returns jsonb language plpgsql stable set search_path='' as $$
declare result jsonb;
begin
 if exists(select 1 from household_private.budget_events(code,timing) e join jsonb_array_elements(plan_lines) l on (l->>'category_id')::uuid=e.category_id where e.event_month=m and e.kind='refund' and l->>'role'='income') then raise exception using errcode='22023',message='A refunded purchase category is planned as income; correct the category or plan';end if;
 with events as materialized(select e.*,coalesce(l->>'role','expense') role from household_private.budget_events(code,timing) e left join jsonb_array_elements(plan_lines) l on (l->>'category_id')::uuid=e.category_id where e.event_month=m),
 grouped as(select category_id,role,household_private.planning_safe(sum(case when kind='outflow' and role='income' then -value when kind in ('outflow','refund') then value when kind='credit' and role='income' then value else 0 end)) actual_minor from events group by category_id,role)
 select jsonb_build_object('categories',coalesce((select jsonb_agg(to_jsonb(g)) from grouped g),'[]'::jsonb),
 'expense_minor',household_private.planning_safe(coalesce((select sum(actual_minor::numeric) from grouped where role='expense'),0)),
 'income_minor',household_private.planning_safe(coalesce((select sum(actual_minor::numeric) from grouped where role='income'),0)),
 'unallocated_credits_minor',household_private.planning_safe(coalesce((select sum(value) from events where kind='refund_remainder' or (kind='credit' and role<>'income')),0))) into result;return result;
end $$;
create function household_private.budget_scope(code text) returns text language sql stable set search_path='' as $$
 select md5(coalesce(string_agg(a.id::text||':'||coalesce(a.archived_at::text,''),',' order by a.id),'')||':'||code) from household_private.accounts a where a.currency=code
$$;
create function household_private.budget_report(target date,code text) returns jsonb language plpgsql stable set search_path='' as $$
declare setting household_private.budget_settings;plan household_private.budget_months;prior date;carry jsonb:='{}';nextcarry jsonb;seen jsonb:='{}';lines jsonb;out_lines jsonb;actuals jsonb;actual jsonb;unbudgeted jsonb;line jsonb;category text;role text;mode text;planned bigint;spent bigint;cap bigint;opening numeric;available numeric;remaining numeric;outcarry numeric;totalplanned numeric;incomeplanned numeric;totalremaining numeric;known boolean;complete boolean;result jsonb;scope text;
begin
 select * into setting from household_private.budget_settings where currency=code;
 if setting.currency is null then return null;end if;
 if (select count(*) from household_private.budget_months where currency=code and month<=target)>600 or (select count(*) from household_private.planning_transactions where currency=code)>50000 then raise exception using errcode='22023',message='Budget history exceeds this report limit';end if;
 scope:=household_private.budget_scope(code);
 for plan in select * from household_private.budget_months where currency=code and month<=target order by month loop
  select coalesce(jsonb_agg(to_jsonb(l)-'month_id' order by l.category_id),'[]'::jsonb) into lines from household_private.budget_lines l where month_id=plan.id;
  actuals:=household_private.budget_actuals(plan.month,code,lines,setting.refund_timing);
  complete:=plan.coverage_confirmed_at is not null and plan.coverage_account_scope=scope and plan.month<date_trunc('month',household_private.planning_today())::date;
  out_lines:='[]';nextcarry:='{}';totalplanned:=0;incomeplanned:=0;totalremaining:=0;known:=true;
  for line in select * from jsonb_array_elements(lines) loop
   category:=line->>'category_id';role:=line->>'role';mode:=line->>'rollover_mode';planned:=(line->>'planned_minor')::bigint;cap:=(line->>'cap_minor')::bigint;
   select e into actual from jsonb_array_elements(actuals->'categories') e where e->>'category_id'=category;spent:=coalesce((actual->>'actual_minor')::bigint,0);
   if role='income' then incomeplanned:=incomeplanned+planned;
    out_lines:=out_lines||jsonb_build_array(line||jsonb_build_object('actual_minor',spent,'remaining_minor',household_private.planning_safe(planned::numeric-spent),'opening_minor',0,'available_minor',planned,'carry_out_minor',0,'provisional',not complete));
   else
    opening:=case when mode='reset' or prior is null then 0 when prior+interval '1 month'<>plan.month then null when carry?category then (carry->>category)::numeric when seen?category then null else 0 end;
    if opening is not null and cap is not null then opening:=least(opening,cap);end if;
    available:=planned+opening;remaining:=available-spent;
    outcarry:=case when mode='reset' then 0 when not complete or remaining is null then null else greatest(remaining,0) end;
    if outcarry is not null and cap is not null then outcarry:=least(outcarry,cap);end if;
    nextcarry:=nextcarry||jsonb_build_object(category,outcarry);totalplanned:=totalplanned+planned;
    if remaining is null then known:=false;else totalremaining:=totalremaining+remaining;end if;
    out_lines:=out_lines||jsonb_build_array(line||jsonb_build_object('actual_minor',spent,'opening_minor',case when opening is null then null else household_private.planning_safe(opening) end,'available_minor',case when available is null then null else household_private.planning_safe(available) end,'remaining_minor',case when remaining is null then null else household_private.planning_safe(remaining) end,'carry_out_minor',case when outcarry is null then null else household_private.planning_safe(outcarry) end,'provisional',not complete));
   end if;
   seen:=seen||jsonb_build_object(category,true);
  end loop;
  select coalesce(jsonb_agg(a||jsonb_build_object('unbudgeted',true)),'[]'::jsonb) into unbudgeted from jsonb_array_elements(actuals->'categories') a where a->>'role'='expense' and not exists(select 1 from jsonb_array_elements(lines) l where l->>'category_id' is not distinct from a->>'category_id');
  totalremaining:=totalremaining-coalesce((select sum((a->>'actual_minor')::numeric) from jsonb_array_elements(unbudgeted) a),0);
  result:=actuals||jsonb_build_object('month',to_char(plan.month,'YYYY-MM'),'currency',code,'coverage_complete',complete,'lines',out_lines,'unbudgeted',unbudgeted,'planned_expense_minor',household_private.planning_safe(totalplanned),'planned_income_minor',household_private.planning_safe(incomeplanned),'remaining_minor',case when known then household_private.planning_safe(totalremaining) end,
   'issues',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'message','A refund link needs attention; restore, correct or unlink its source records')) from household_private.budget_refund_context c where not valid and (purchase_currency=code or refund_currency=code)),'[]'::jsonb));
  carry:=nextcarry;prior:=plan.month;
 end loop;
 if prior is distinct from target then return null;end if;return result;
end $$;
create function household_private.budget_workspace(m date,code text) returns jsonb language plpgsql stable set search_path='' as $$
declare result jsonb;plan household_private.budget_months;setting household_private.budget_settings;
begin
 select * into plan from household_private.budget_months where month=m and currency=code;
 select * into setting from household_private.budget_settings where currency=code;
 if (select count(*) from household_private.budget_refund_context where purchase_currency=code or refund_currency=code)>5000 then raise exception using errcode='22023',message='Refund history exceeds this workspace limit';end if;
 select jsonb_build_object('currencies',coalesce((select jsonb_agg(currency order by currency) from (select currency from household_private.accounts union select currency from household_private.budget_settings union select code) c),'[]'::jsonb),
 'month',to_char(m,'YYYY-MM'),'currency',code,'anchor_month',to_char(setting.anchor_month,'YYYY-MM'),'refund_timing',setting.refund_timing,'settings_revision',coalesce(setting.revision,0),
 'categories',coalesce((select jsonb_agg(to_jsonb(c) order by c.name,c.id) from household_private.categories c),'[]'::jsonb),
 'plan',case when plan.id is null then null else (to_jsonb(plan)-array['coverage_confirmed_by','coverage_account_scope'])||jsonb_build_object('month',to_char(plan.month,'YYYY-MM'),'lines',coalesce((select jsonb_agg(to_jsonb(l)-'month_id' order by l.category_id) from household_private.budget_lines l where l.month_id=plan.id),'[]'::jsonb)) end,
 'report',household_private.budget_report(m,code),
 'profile',coalesce((select to_jsonb(p)-array['singleton','revision'] from household_private.budget_comparison_profile p),'{}'::jsonb),'profile_revision',coalesce((select revision from household_private.budget_comparison_profile),0),
 'benchmark_cohort',coalesce((select cohort_label from household_private.budget_benchmark_preferences),'Canada · All quintiles'),'benchmark_revision',coalesce((select revision from household_private.budget_benchmark_preferences),0),
 'mappings',coalesce((select jsonb_agg(to_jsonb(b)-'enabled' order by b.category_id) from household_private.budget_benchmark_mappings b where b.enabled),'[]'::jsonb),
 'refund_links',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('issue',case when not valid then 'Linked records changed or are in Trash; correct or unlink this refund' end) order by c.refund_date desc,c.id) from household_private.budget_refund_context c where (purchase_currency=code or refund_currency=code) and (date_trunc('month',purchase_date)::date=m or date_trunc('month',refund_date)::date=m or not valid)),'[]'::jsonb),
 'can_confirm_coverage',plan.id is not null and m<date_trunc('month',household_private.planning_today())::date) into result;
 if octet_length(result::text)>8000000 then raise exception using errcode='22023',message='Budget workspace is too large';end if;return result;
end $$;
create function household_private.budget_refund_action(op text,p jsonb,actor uuid) returns jsonb language plpgsql set search_path='' as $$
declare link household_private.budget_refund_links;purchase household_private.planning_transactions;refund household_private.planning_transactions;pid uuid;rid uuid;value bigint;code text;
begin
 if op='budget_unlink_refund' then
  perform household_private.planning_check(p,array['id','revision']);select * into link from household_private.budget_refund_links where id=(p->>'id')::uuid;pid:=link.purchase_id;rid:=link.refund_id;
 else
  perform household_private.planning_check(p,array['currency','purchase_id','refund_id','purchase_revision','refund_revision','amount_minor']);pid:=(p->>'purchase_id')::uuid;rid:=(p->>'refund_id')::uuid;
 end if;
 perform t.id from household_private.transactions t where t.id in(pid,rid) order by t.id for update;
 if op='budget_unlink_refund' then
  select * into link from household_private.budget_refund_links where id=(p->>'id')::uuid for update;
  if link.id is null then raise exception using errcode='P0002',message='Refund link not found';end if;
  if link.revision is distinct from household_private.planning_int(p,'revision',1,2147483647) or link.unlinked_at is not null then raise exception using errcode='40001',message='Refund link changed; reload';end if;
  update household_private.budget_refund_links set unlinked_at=now(),unlinked_by=actor,revision=budget_refund_links.revision+1 where id=link.id returning * into link;
 else
  code:=household_private.planning_text(p,'currency',3,3);value:=household_private.planning_int(p,'amount_minor',1,9007199254740991);
  select * into purchase from household_private.planning_transactions where id=pid;select * into refund from household_private.planning_transactions where id=rid;
  if purchase.id is null or refund.id is null or pid=rid or value is null or purchase.amount_minor>=0 or refund.amount_minor<=0 or purchase.currency<>code or refund.currency<>code or purchase.flow_type<>'regular' or refund.flow_type<>'regular' or purchase.deleted_at is not null or refund.deleted_at is not null then raise exception using errcode='22023',message='Choose a regular purchase and credit in the same currency';end if;
  if purchase.revision is distinct from household_private.planning_int(p,'purchase_revision',1,2147483647) or refund.revision is distinct from household_private.planning_int(p,'refund_revision',1,2147483647) then raise exception using errcode='40001',message='A refund source changed; reload candidates';end if;
  if exists(select 1 from household_private.budget_refund_links where purchase_id=pid and refund_id=rid and unlinked_at is null) then raise exception using errcode='40001',message='This refund pair is already linked; reload';end if;
  if value::numeric+coalesce((select sum(amount_minor::numeric) from household_private.budget_refund_links where purchase_id=pid and unlinked_at is null),0)>-purchase.amount_minor::numeric or value::numeric+coalesce((select sum(amount_minor::numeric) from household_private.budget_refund_links where refund_id=rid and unlinked_at is null),0)>refund.amount_minor::numeric then raise exception using errcode='22023',message='Refund allocation exceeds the remaining purchase or credit';end if;
  insert into household_private.budget_refund_links(purchase_id,refund_id,amount_minor,created_by) values(pid,rid,value,actor) returning * into link;
 end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,op,link.id);return jsonb_build_object('id',link.id,'revision',link.revision);
end $$;
create function household_private.budget_known_cohort(label text) returns boolean language sql immutable set search_path='' as $$ select '["Alberta \u00b7 All quintiles", "Alberta \u00b7 Fourth quintile", "Alberta \u00b7 Highest quintile", "Alberta \u00b7 Lowest quintile", "Alberta \u00b7 Second quintile", "Alberta \u00b7 Third quintile", "Atlantic Region \u00b7 All quintiles", "Atlantic Region \u00b7 Fourth quintile", "Atlantic Region \u00b7 Highest quintile", "Atlantic Region \u00b7 Lowest quintile", "Atlantic Region \u00b7 Second quintile", "Atlantic Region \u00b7 Third quintile", "British Columbia \u00b7 All quintiles", "British Columbia \u00b7 Fourth quintile", "British Columbia \u00b7 Highest quintile", "British Columbia \u00b7 Lowest quintile", "British Columbia \u00b7 Second quintile", "British Columbia \u00b7 Third quintile", "Canada \u00b7 All quintiles", "Canada \u00b7 Fourth quintile", "Canada \u00b7 Highest quintile", "Canada \u00b7 Lowest quintile", "Canada \u00b7 Second quintile", "Canada \u00b7 Third quintile", "Manitoba \u00b7 All quintiles", "Manitoba \u00b7 Fourth quintile", "Manitoba \u00b7 Highest quintile", "Manitoba \u00b7 Lowest quintile", "Manitoba \u00b7 Second quintile", "Manitoba \u00b7 Third quintile", "New Brunswick \u00b7 All quintiles", "New Brunswick \u00b7 Fourth quintile", "New Brunswick \u00b7 Highest quintile", "New Brunswick \u00b7 Lowest quintile", "New Brunswick \u00b7 Second quintile", "New Brunswick \u00b7 Third quintile", "Newfoundland and Labrador \u00b7 All quintiles", "Newfoundland and Labrador \u00b7 Fourth quintile", "Newfoundland and Labrador \u00b7 Highest quintile", "Newfoundland and Labrador \u00b7 Lowest quintile", "Newfoundland and Labrador \u00b7 Second quintile", "Newfoundland and Labrador \u00b7 Third quintile", "Nova Scotia \u00b7 All quintiles", "Nova Scotia \u00b7 Fourth quintile", "Nova Scotia \u00b7 Highest quintile", "Nova Scotia \u00b7 Lowest quintile", "Nova Scotia \u00b7 Second quintile", "Nova Scotia \u00b7 Third quintile", "Ontario \u00b7 All quintiles", "Ontario \u00b7 Fourth quintile", "Ontario \u00b7 Highest quintile", "Ontario \u00b7 Lowest quintile", "Ontario \u00b7 Second quintile", "Ontario \u00b7 Third quintile", "Prairie Region \u00b7 All quintiles", "Prairie Region \u00b7 Fourth quintile", "Prairie Region \u00b7 Highest quintile", "Prairie Region \u00b7 Lowest quintile", "Prairie Region \u00b7 Second quintile", "Prairie Region \u00b7 Third quintile", "Prince Edward Island \u00b7 All quintiles", "Prince Edward Island \u00b7 Fourth quintile", "Prince Edward Island \u00b7 Highest quintile", "Prince Edward Island \u00b7 Lowest quintile", "Prince Edward Island \u00b7 Second quintile", "Prince Edward Island \u00b7 Third quintile", "Quebec \u00b7 All quintiles", "Quebec \u00b7 Fourth quintile", "Quebec \u00b7 Highest quintile", "Quebec \u00b7 Lowest quintile", "Quebec \u00b7 Second quintile", "Quebec \u00b7 Third quintile", "Saskatchewan \u00b7 All quintiles", "Saskatchewan \u00b7 Fourth quintile", "Saskatchewan \u00b7 Highest quintile", "Saskatchewan \u00b7 Lowest quintile", "Saskatchewan \u00b7 Second quintile", "Saskatchewan \u00b7 Third quintile"]'::jsonb ? label $$;
create function household_private.budget_dispatch(operation text,payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();_actor_role text:=household_private.member_role();p jsonb:=payload;code text;m date;source_month date;setting household_private.budget_settings;plan household_private.budget_months;source_plan household_private.budget_months;credit household_private.planning_transactions;pref household_private.budget_benchmark_preferences;profile household_private.budget_comparison_profile;line jsonb;ident uuid;revision integer;off integer;lim integer;q text;timing text;cohort text;result jsonb;fresh boolean;category uuid;planned bigint;cap bigint;mode text;line_role text;
begin
 if operation in ('budget_link_refund','budget_unlink_refund') then return household_private.budget_refund_action(operation,p,actor);end if;
 if operation='budget_save_profile' then
  perform household_private.planning_check(p,array['revision','adults','children','province','tenure','income_quintile']);perform pg_advisory_xact_lock(79125,0);select * into profile from household_private.budget_comparison_profile for update;
  if coalesce(profile.revision,0) is distinct from household_private.planning_int(p,'revision',0,2147483647) then raise exception using errcode='40001',message='Household profile changed; reload';end if;
  insert into household_private.budget_comparison_profile(singleton,adults,children,province,tenure,income_quintile) values(true,household_private.planning_int(p,'adults',1,30),household_private.planning_int(p,'children',0,30),household_private.planning_text(p,'province',0,80),household_private.planning_text(p,'tenure',0,10),household_private.planning_text(p,'income_quintile',0,30))
  on conflict(singleton) do update set adults=excluded.adults,children=excluded.children,province=excluded.province,tenure=excluded.tenure,income_quintile=excluded.income_quintile,revision=budget_comparison_profile.revision+1;
  insert into household_private.audit_events(actor_id,action) values(actor,operation);return '{}'::jsonb;
 end if;
 if operation='budget_save_benchmarks' then
  perform household_private.planning_check(p,array['revision','cohort_label','source_table','reference_year','mappings']);perform pg_advisory_xact_lock(79125,1);select * into pref from household_private.budget_benchmark_preferences for update;
  if coalesce(pref.revision,0) is distinct from household_private.planning_int(p,'revision',0,2147483647) then raise exception using errcode='40001',message='Comparison settings changed; reload';end if;
  cohort:=household_private.planning_text(p,'cohort_label',1,200);
  if p->>'source_table'<>'11-10-0223-01' or p->>'source_table' is null or household_private.planning_int(p,'reference_year',1900,2100) is distinct from 2023 or not household_private.budget_known_cohort(cohort) then raise exception using errcode='22023',message='Choose a published Statistics Canada group and source year';end if;
  if jsonb_typeof(p->'mappings') is distinct from 'array' or jsonb_array_length(p->'mappings')>4 then raise exception using errcode='22023',message='Choose up to four distinct category comparisons';end if;
  if (select count(distinct v->>'category_id') from jsonb_array_elements(p->'mappings') v)<>jsonb_array_length(p->'mappings') or (select count(distinct v->>'expenditure_label') from jsonb_array_elements(p->'mappings') v)<>jsonb_array_length(p->'mappings') then raise exception using errcode='22023',message='Comparison categories and source series must be distinct';end if;
  for line in select * from jsonb_array_elements(p->'mappings') loop
   perform household_private.planning_check(line,array['category_id','source_table','reference_year','expenditure_label','comparable','note']);
   if line->>'source_table' is distinct from '11-10-0223-01' or household_private.planning_int(line,'reference_year',1900,2100) is distinct from 2023 or coalesce(line->>'expenditure_label','') not in ('Food purchased from stores','Food purchased from restaurants','Clothing and accessories','Recreation') or not exists(select 1 from household_private.categories where id=(line->>'category_id')::uuid and accounting_behavior='regular') then raise exception using errcode='22023',message='Choose an equivalent regular category and published series';end if;
   perform household_private.planning_bool(line,'comparable');perform household_private.planning_text(line,'note',0,1000);
  end loop;
  insert into household_private.budget_benchmark_preferences(singleton,cohort_label,source_table,reference_year) values(true,cohort,'11-10-0223-01',2023) on conflict(singleton) do update set cohort_label=excluded.cohort_label,source_table=excluded.source_table,reference_year=excluded.reference_year,revision=budget_benchmark_preferences.revision+1;
  update household_private.budget_benchmark_mappings set enabled=false;
  insert into household_private.budget_benchmark_mappings(category_id,source_table,reference_year,expenditure_label,comparable,note) select (v->>'category_id')::uuid,'11-10-0223-01',2023,v->>'expenditure_label',household_private.planning_bool(v,'comparable'),household_private.planning_text(v,'note',0,1000) from jsonb_array_elements(p->'mappings') v on conflict(category_id) do update set source_table=excluded.source_table,reference_year=excluded.reference_year,expenditure_label=excluded.expenditure_label,comparable=excluded.comparable,note=excluded.note,enabled=true;
  insert into household_private.audit_events(actor_id,action) values(actor,operation);return '{}'::jsonb;
 end if;
 code:=household_private.planning_text(p,'currency',3,3);if code !~ '^[A-Z]{3}$' then raise exception using errcode='22023',message='Choose a currency';end if;
 if operation='budget_set_refund_timing' then
  perform household_private.planning_check(p,array['currency','revision','refund_timing']);perform pg_advisory_xact_lock(79124,hashtext(code));select * into setting from household_private.budget_settings where currency=code for update;
  if setting.currency is null then raise exception using errcode='P0002',message='Start a budget before changing refund timing';end if;
  if setting.revision is distinct from household_private.planning_int(p,'revision',1,2147483647) then raise exception using errcode='40001',message='Budget settings changed; reload';end if;
  timing:=household_private.planning_text(p,'refund_timing',1,20);if timing not in ('received','purchase') then raise exception using errcode='22023',message='Choose refund timing';end if;
  update household_private.budget_settings set refund_timing=timing,revision=budget_settings.revision+1,updated_at=now() where currency=code;insert into household_private.audit_events(actor_id,action) values(actor,operation);return '{}'::jsonb;
 end if;
 m:=household_private.planning_month(p,'month');
 if operation='budget_get_workspace' then perform household_private.planning_check(p,array['month','currency']);return household_private.budget_workspace(m,code);end if;
 if operation='budget_category_activity' then
  perform household_private.planning_check(p,array['month','currency','category_id','offset','limit']);category:=nullif(p->>'category_id','')::uuid;off:=household_private.planning_int(p,'offset',0,1000000,0);lim:=household_private.planning_int(p,'limit',1,50,50);select refund_timing into timing from household_private.budget_settings where currency=code;
  if timing is null then raise exception using errcode='P0002',message='Budget not found';end if;
  with f as materialized(select e.transaction_id id,e.peer_id,e.kind,household_private.planning_safe(e.value) budget_impact_minor,t.date,t.description,t.account_name,t.currency,t.amount_minor,peer.description peer_description,peer.date peer_date from household_private.budget_events(code,timing) e join household_private.planning_transactions t on t.id=e.transaction_id left join household_private.planning_transactions peer on peer.id=e.peer_id where e.event_month=m and e.category_id is not distinct from category and e.kind in ('outflow','refund')),
  page as(select * from f order by date desc,id,peer_id limit lim offset off)
  select jsonb_build_object('total',(select count(*) from f),'rows',coalesce((select jsonb_agg(to_jsonb(t) order by date desc,id,peer_id) from page t),'[]'::jsonb)) into result;return result;
 end if;
 if operation in ('budget_refund_credits','budget_refund_candidates') then
  perform household_private.planning_check(p,array['month','currency','query','offset','limit','refund_id']);q:=household_private.planning_text(p,'query',0,500);off:=household_private.planning_int(p,'offset',0,1000000,0);lim:=household_private.planning_int(p,'limit',1,50,50);
  if operation='budget_refund_candidates' then select * into credit from household_private.planning_transactions where id=(p->>'refund_id')::uuid;
   if credit.id is null or credit.amount_minor<=0 or credit.deleted_at is not null or credit.flow_type<>'regular' or credit.currency<>code then raise exception using errcode='22023',message='Choose an active credit in this currency';end if;
  end if;
  with f as materialized(select t.*,household_private.planning_safe(abs(t.amount_minor::numeric)-coalesce((select sum(l.amount_minor::numeric) from household_private.budget_refund_links l where l.unlinked_at is null and case when operation='budget_refund_credits' then l.refund_id=t.id else l.purchase_id=t.id end),0)) available_minor from household_private.planning_transactions t where t.currency=code and t.deleted_at is null and t.flow_type='regular' and case when operation='budget_refund_credits' then t.amount_minor>0 and date_trunc('month',t.date)::date=m else t.amount_minor<0 end and strpos(lower(concat_ws(' ',t.description,t.account_name,t.category_name,t.tags_text)),lower(q))>0),
  usable as(select * from f where available_minor>0),page as(select * from usable order by date desc,id limit lim offset off)
  select jsonb_build_object('total',(select count(*) from usable),'rows',coalesce((select jsonb_agg(to_jsonb(t) order by date desc,id) from page t),'[]'::jsonb)) into result;return result;
 end if;
 if operation='budget_create_month' then
  perform household_private.planning_check(p,array['month','currency','refund_timing','settings_revision','copy_from']);timing:=household_private.planning_text(p,'refund_timing',1,20);if timing not in ('received','purchase') then raise exception using errcode='22023',message='Choose refund timing';end if;
  perform pg_advisory_xact_lock(79124,hashtext(code));select * into setting from household_private.budget_settings where currency=code for update;
  if setting.currency is null then
   if household_private.planning_int(p,'settings_revision',0,2147483647) is distinct from 0 then raise exception using errcode='40001',message='Budget settings changed; reload';end if;
   insert into household_private.budget_settings(currency,refund_timing,anchor_month) values(code,timing,m) returning * into setting;
  else
   if setting.refund_timing<>timing or setting.revision is distinct from household_private.planning_int(p,'settings_revision',0,2147483647) then raise exception using errcode='40001',message='Budget settings changed; reload';end if;
   if m<setting.anchor_month then raise exception using errcode='22023',message='This currency budget starts '||to_char(setting.anchor_month,'YYYY-MM')||'; earlier anchor changes require separate review';end if;
  end if;
  select * into plan from household_private.budget_months where currency=code and month=m for update;if plan.id is not null then return jsonb_build_object('id',plan.id,'already_exists',true);end if;
  if p?'copy_from' and p->'copy_from'<>'null'::jsonb then source_month:=household_private.planning_month(p,'copy_from');if source_month<>m-interval '1 month' then raise exception using errcode='22023',message='Copy from the immediately previous month';end if;
   select * into source_plan from household_private.budget_months where currency=code and month=source_month for share;if source_plan.id is null then raise exception using errcode='P0002',message='Previous month has no saved plan';end if;
  end if;
  insert into household_private.budget_months(month,currency) values(m,code) returning * into plan;
  if source_plan.id is not null then insert into household_private.budget_lines(month_id,category_id,role,planned_minor,rollover_mode,cap_minor) select plan.id,category_id,role,planned_minor,rollover_mode,cap_minor from household_private.budget_lines where month_id=source_plan.id;end if;
  ident:=plan.id;
 elsif operation in ('budget_save_line','budget_confirm_coverage') then
  if operation='budget_save_line' then perform household_private.planning_check(p,array['month','currency','plan_revision','category_id','role','planned_minor','rollover_mode','cap_minor']);
  else perform household_private.planning_check(p,array['month','currency','plan_revision','confirmed']);end if;
  select * into plan from household_private.budget_months where currency=code and month=m for update;
  if plan.id is null then raise exception using errcode='P0002',message='Start this month before editing its budget';end if;
  if plan.revision is distinct from household_private.planning_int(p,'plan_revision',1,2147483647) then raise exception using errcode='40001',message='Monthly plan changed; reload before saving';end if;
  if operation='budget_confirm_coverage' then
   if m>=date_trunc('month',household_private.planning_today())::date or not household_private.planning_bool(p,'confirmed') then raise exception using errcode='22023',message='Only completed months can have confirmed import coverage';end if;
   update household_private.budget_months set coverage_confirmed_at=now(),coverage_confirmed_by=actor,coverage_account_scope=household_private.budget_scope(code),revision=budget_months.revision+1,updated_at=now() where id=plan.id;
  else
   category:=(p->>'category_id')::uuid;select id into ident from household_private.categories where id=category and accounting_behavior='regular' for share;if ident is null then raise exception using errcode='22023',message='Choose a regular spending or income category';end if;
   line_role:=household_private.planning_text(p,'role',1,10);mode:=household_private.planning_text(p,'rollover_mode',1,20);planned:=household_private.planning_int(p,'planned_minor',0,9007199254740991);cap:=household_private.planning_int(p,'cap_minor',0,9007199254740991);
   if planned is null or line_role not in ('expense','income') or mode not in ('reset','unused') or (line_role='income' and (mode<>'reset' or cap is not null)) or (mode='reset' and cap is not null) then raise exception using errcode='22023',message='Check the amount, plan type and rollover settings';end if;
   insert into household_private.budget_lines(month_id,category_id,role,planned_minor,rollover_mode,cap_minor) values(plan.id,category,line_role,planned,mode,cap) on conflict(month_id,category_id) do update set role=excluded.role,planned_minor=excluded.planned_minor,rollover_mode=excluded.rollover_mode,cap_minor=excluded.cap_minor;
   update household_private.budget_months set revision=budget_months.revision+1,updated_at=now() where id=plan.id;
  end if;
  ident:=plan.id;
 else raise exception using errcode='22023',message='Unknown budget operation';end if;
 insert into household_private.audit_events(actor_id,action,target_id) values(actor,operation,ident);return jsonb_build_object('id',ident);
end $$;
create function public.household_budget_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$ select household_private.budget_dispatch(operation,payload) $$;

-- Only the guarded entry points and exact-path storage predicate are callable.
do $$ declare proc regprocedure;
begin
 for proc in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='household_private' and p.proname ~ '^(planning_|tax_|budget_)' loop execute format('revoke all on function %s from public,anon,authenticated',proc);end loop;
end $$;
grant execute on function household_private.tax_dispatch(text,jsonb),household_private.budget_dispatch(text,jsonb),household_private.tax_document_permission(text,text) to authenticated;
revoke all on function public.household_tax_v1(text,jsonb),public.household_budget_v1(text,jsonb) from public,anon,authenticated;
grant execute on function public.household_tax_v1(text,jsonb),public.household_budget_v1(text,jsonb) to authenticated;
notify pgrst,'reload schema';
