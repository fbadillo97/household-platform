-- Website identity fields are private and independent of accounting.
alter table household_private.payees add column website text;
alter table household_private.payees add column website_logo bytea check(household_private.visual_png_valid(website_logo) and octet_length(website_logo)<=16384);
alter table household_private.payees add column website_logo_source text;
alter table household_private.payees add constraint payee_website_check check(website is null or (length(website)<=1000 and website ~ '^https://[^[:space:]<>@]+$'));
alter table household_private.payees add constraint payee_website_logo_pair check((website_logo is null)=(website_logo_source is null) and (website_logo is null or website is not null));
alter function household_private.payee_action(text,jsonb) rename to payee_action_before_website;
create function household_private.payee_action(operation text,payload jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare role text:=household_private.member_role();actor uuid:=household_private.identity_id();result jsonb;ident uuid;site text;logo bytea;source text;
begin
 if payload?'website' then
 site:=nullif(btrim(payload->>'website'),'');source:=nullif(payload->>'website_logo_source','');
 if operation not in ('create_payee','update_payee') or (site is not null and (length(site)>1000 or site !~ '^https://[^[:space:]<>@]+$')) then raise exception using errcode='22023',message='Use a public HTTPS website';end if;
 if nullif(payload->>'website_logo_base64','') is not null then
 if length(payload->>'website_logo_base64')>22000 or payload->>'website_logo_base64' !~ '^[A-Za-z0-9+/]+={0,2}$'then raise exception using errcode='22023',message='Use a small website icon';end if;
 logo:=decode(payload->>'website_logo_base64','base64');
 if not household_private.visual_png_valid(logo) or octet_length(logo)>16384 or site is null or source is null or length(source)>1000 or source !~ '^https://[^[:space:]<>@]+$'then raise exception using errcode='22023',message='Use a small PNG and HTTPS source';end if;
 elsif source is not null then raise exception using errcode='22023',message='Logo source requires an image';end if;
 elsif payload?'website_logo_base64' or payload?'website_logo_source'then raise exception using errcode='22023',message='Provide the website with its logo';end if;
 result:=household_private.payee_action_before_website(operation,payload-array['website','website_logo_base64','website_logo_source']);ident:=(result->>'id')::uuid;
 if payload?'website'then update household_private.payees set website=site,website_logo=logo,website_logo_source=source where id=ident;insert into household_private.audit_events(actor_id,action,target_id)values(actor,'save_payee_website',ident);end if;
 return result;
end $$;
create function household_private.payee_website_access(operation text,payload jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();role text:=household_private.member_role();
begin
 if operation<>'payee_website_access' or payload is distinct from '{}'::jsonb then raise exception using errcode='22023',message='Unknown website operation';end if;
 perform pg_advisory_xact_lock(hashtextextended('website-logo:'||actor::text,0));
 if (select count(*)from household_private.audit_events where actor_id=actor and action='fetch_payee_website_logo' and created_at>now()-interval '10 minutes')>=30 then raise exception using errcode='54000',message='Please wait before fetching more website icons';end if;
 insert into household_private.audit_events(actor_id,action)values(actor,'fetch_payee_website_logo');return '{"allowed":true}'::jsonb;
end $$;
revoke all on function household_private.payee_website_access(text,jsonb),household_private.payee_action(text,jsonb),household_private.payee_action_before_website(text,jsonb)from public,anon,authenticated;
grant execute on function household_private.payee_website_access(text,jsonb)to authenticated;
create function public.household_payee_websites_v1(operation text,payload jsonb default '{}'::jsonb)returns jsonb language sql security invoker set search_path='' as $$select household_private.payee_website_access(operation,payload)$$;
revoke all on function public.household_payee_websites_v1(text,jsonb)from public,anon,authenticated;
grant execute on function public.household_payee_websites_v1(text,jsonb)to authenticated;
create or replace function household_private.payee_list()returns jsonb language plpgsql security definer set search_path='' as $$
declare role text:=household_private.member_role();result jsonb;
begin
 if (select count(*)from household_private.payees)>2000 then raise exception using errcode='54000',message='Payee directory exceeds 2000 entries';end if;
 select coalesce(jsonb_agg((to_jsonb(p)-'website_logo')||jsonb_build_object('website_logo_base64',replace(encode(p.website_logo,'base64'),E'\n',''),
 'aliases',coalesce((select jsonb_agg(a.description order by a.match_key)from household_private.payee_aliases a where a.payee_id=p.id),'[]'),
 'tags',coalesce((select jsonb_agg(to_jsonb(t)order by lower(t.name))from household_private.payee_tags t join household_private.payee_tag_links l on l.tag_id=t.id where l.payee_id=p.id),'[]'),
 'transaction_count',(select count(*)from household_private.transactions t where t.payee_id=p.id and t.deleted_at is null),
 'last_transaction',(select max(date)from household_private.transactions t where t.payee_id=p.id and t.deleted_at is null))order by lower(p.name),p.id),'[]')into result from household_private.payees p;return result;
end $$;

notify pgrst,'reload schema';
