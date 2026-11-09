-- Small private logo catalog and presentation overrides. No ledger changes or external requests.
create function household_private.visual_png_valid(png bytea) returns boolean language sql immutable set search_path='' as $$
 select case when png is null then true when octet_length(png)<33 or octet_length(png)>65536 then false
 else substring(png from 1 for 8)=decode('89504e470d0a1a0a','hex') and substring(png from 13 for 4)=decode('49484452','hex') and
 get_byte(png,16)=0 and get_byte(png,17)=0 and get_byte(png,20)=0 and get_byte(png,21)=0 and
 get_byte(png,18)*256+get_byte(png,19) between 1 and 256 and get_byte(png,22)*256+get_byte(png,23) between 1 and 256 end
$$;
create table household_private.visual_brands(
 key text primary key check(key ~ '^[a-z0-9][a-z0-9-]{0,59}$'),name text not null check(length(name) between 1 and 120),
 aliases text[] not null default '{}',png bytea check(household_private.visual_png_valid(png)),source_url text not null check(source_url ~ '^https://[^[:space:]]+$' and length(source_url)<=1000),
 revision integer not null default 1,updated_at timestamptz not null default now());
create table household_private.visual_preferences(
 entity_type text not null check(entity_type in ('category','account','payee')),entity_id uuid not null,
 brand_mode text not null default 'auto' check(brand_mode in ('auto','brand','none')),brand_key text references household_private.visual_brands(key),
 icon text check(icon in ('shapes','shopping-basket','house','car','utensils','coffee','zap','heart-pulse','graduation-cap','plane','gift','shirt','wrench','baby','paw-print','wallet','landmark','credit-card','chart-no-axes-combined','hand-coins','arrow-left-right','banknote','smartphone','shield-check','briefcase','receipt','calendar-days','files')),
 tone text check(tone in ('teal','green','purple','amber','blue','rose','neutral')),revision integer not null default 1,updated_at timestamptz not null default now(),
 primary key(entity_type,entity_id),check((brand_mode='brand')=(brand_key is not null)),check(entity_type<>'category' or brand_mode='auto'));
create index visual_preferences_brand_idx on household_private.visual_preferences(brand_key);
alter table household_private.visual_brands enable row level security;alter table household_private.visual_preferences enable row level security;
revoke all on household_private.visual_brands,household_private.visual_preferences from public,anon,authenticated;
create function household_private.visual_dispatch(operation text,payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();actor_role text:=household_private.member_role();p jsonb:=payload;kind text;ident uuid;mode text;brand text;glyph text;tint text;rev integer;newrev integer;label text;source text;logo_aliases text[];logo_png bytea;result jsonb;
begin
 if operation='visuals_get_catalog' then
  perform household_private.planning_check(p,'{}');
  select jsonb_build_object('brands',coalesce((select jsonb_agg(jsonb_build_object('key',b.key,'name',b.name,'aliases',b.aliases,'png_base64',replace(encode(b.png,'base64'),E'\n',''),'source_url',b.source_url,'revision',b.revision) order by b.name,b.key) from household_private.visual_brands b),'[]'::jsonb),
  'preferences',coalesce((select jsonb_agg(to_jsonb(v) order by v.entity_type,v.entity_id) from household_private.visual_preferences v),'[]'::jsonb)) into result;return result;
 elsif operation='visuals_save_preference' then
  perform household_private.planning_check(p,array['entity_type','entity_id','brand_mode','brand_key','icon','tone','revision']);
  kind:=household_private.planning_text(p,'entity_type',1,10);ident:=(p->>'entity_id')::uuid;mode:=household_private.planning_text(p,'brand_mode',1,10,'auto');brand:=nullif(household_private.planning_text(p,'brand_key',0,60),'');glyph:=nullif(household_private.planning_text(p,'icon',0,40),'');tint:=nullif(household_private.planning_text(p,'tone',0,20),'');rev:=household_private.planning_int(p,'revision',0,2147483646);
  if rev is null or ident is null or kind not in ('category','account','payee') or mode not in ('auto','none','brand') or (mode='brand')<>(brand is not null) or (kind='category' and mode<>'auto') then raise exception using errcode='22023',message='Choose a valid appearance';end if;
  if not (case kind when 'category' then exists(select 1 from household_private.categories where id=ident) when 'account' then exists(select 1 from household_private.accounts where id=ident) when 'payee' then exists(select 1 from household_private.payees where id=ident) else false end) then raise exception using errcode='22023',message='Record no longer exists';end if;
  if brand is not null and not exists(select 1 from household_private.visual_brands where key=brand) then raise exception using errcode='22023',message='Choose a saved logo';end if;
  if rev=0 then
   insert into household_private.visual_preferences(entity_type,entity_id,brand_mode,brand_key,icon,tone) values(kind,ident,mode,brand,glyph,tint) on conflict do nothing returning revision into newrev;
  else
   update household_private.visual_preferences set brand_mode=mode,brand_key=brand,icon=glyph,tone=tint,revision=revision+1,updated_at=now() where entity_type=kind and entity_id=ident and revision=rev returning revision into newrev;
  end if;
  if newrev is null then raise exception using errcode='40001',message='Appearance changed elsewhere. Reload saved appearance before trying again.';end if;
  return jsonb_build_object('revision',newrev);
 elsif operation='visuals_save_brand' then
  if actor_role<>'owner' then raise exception using errcode='42501',message='Only the household owner can save shared logos';end if;
  perform household_private.planning_check(p,array['key','name','aliases','png_base64','source_url','revision']);
  brand:=household_private.planning_text(p,'key',1,60);label:=household_private.planning_text(p,'name',1,120);source:=household_private.planning_text(p,'source_url',1,1000);rev:=household_private.planning_int(p,'revision',0,2147483646);
  if rev is null or brand !~ '^[a-z0-9][a-z0-9-]{0,59}$' or source !~ '^https://[^[:space:]]+$' or jsonb_typeof(p->'aliases') is distinct from 'array' then raise exception using errcode='22023',message='Use a brand key, official HTTPS source and aliases';end if;
  if jsonb_array_length(p->'aliases')>20 or exists(select 1 from jsonb_array_elements(p->'aliases') a where jsonb_typeof(a)<>'string' or length(btrim(a#>>'{}')) not between 2 and 120) then raise exception using errcode='22023',message='Use up to 20 clear brand aliases';end if;
  select coalesce(array_agg(distinct btrim(value)),'{}') into logo_aliases from jsonb_array_elements_text(p->'aliases');
  if p->'png_base64' is distinct from 'null'::jsonb and p?'png_base64' then
   label:=household_private.planning_text(p,'name',1,120);source:=household_private.planning_text(p,'source_url',1,1000);
   if jsonb_typeof(p->'png_base64')<>'string' or length(p->>'png_base64')>90000 or p->>'png_base64' !~ '^[A-Za-z0-9+/]+={0,2}$' then raise exception using errcode='22023',message='Use a small PNG image';end if;
   logo_png:=decode(p->>'png_base64','base64');if not household_private.visual_png_valid(logo_png) then raise exception using errcode='22023',message='Use a PNG up to 256 pixels and 64 KB';end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('household_visual_brands',0));
  if rev=0 then
   if (select count(*) from household_private.visual_brands)>=128 then raise exception using errcode='22023',message='Logo collection is full';end if;
   insert into household_private.visual_brands(key,name,aliases,png,source_url) values(brand,label,logo_aliases,logo_png,source) on conflict do nothing returning revision into newrev;
  else
   update household_private.visual_brands set name=label,aliases=logo_aliases,png=logo_png,source_url=source,revision=revision+1,updated_at=now() where key=brand and revision=rev returning revision into newrev;
  end if;
  if newrev is null then raise exception using errcode='40001',message='Logo changed elsewhere. Read the current logo revision before trying again.';end if;return jsonb_build_object('key',brand,'revision',newrev);
 end if;
 raise exception using errcode='22023',message='Unknown visual operation';
end $$;
revoke all on function household_private.visual_png_valid(bytea),household_private.visual_dispatch(text,jsonb) from public,anon,authenticated;
grant execute on function household_private.visual_dispatch(text,jsonb) to authenticated;
create function public.household_visuals_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select household_private.visual_dispatch(operation,payload)$$;
revoke all on function public.household_visuals_v1(text,jsonb) from public,anon,authenticated;grant execute on function public.household_visuals_v1(text,jsonb) to authenticated;
notify pgrst,'reload schema';
