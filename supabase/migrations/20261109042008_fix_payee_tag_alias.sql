-- Separate the PL/pgSQL record variable from the tag-list SQL alias.
create or replace function household_private.payee_tag_action(operation text,p jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=household_private.identity_id();role text:=household_private.member_role();ident uuid;result jsonb;stored_tag household_private.payee_tags;r jsonb;n integer;
begin
 if jsonb_typeof(p) is distinct from 'object' or octet_length(p::text)>30000 then raise exception using errcode='22023',message='Invalid payee tag request';end if;
 if operation='list_payee_tags' then
 if p<>'{}'::jsonb then raise exception using errcode='22023',message='Unsupported tag filter';end if;
 select coalesce(jsonb_agg(to_jsonb(tag_row)||jsonb_build_object('payee_count',(select count(*) from household_private.payee_tag_links l where l.tag_id=tag_row.id)) order by lower(tag_row.name),tag_row.id),'[]') into result from household_private.payee_tags tag_row;return result;end if;
 if operation in ('create_payee_tag','update_payee_tag')then
 if exists(select 1 from jsonb_object_keys(p)k where k not in ('id','revision','name','archived'))or jsonb_typeof(p->'name') is distinct from 'string' or length(btrim(p->>'name'))not between 1 and 60 or (p?'archived' and jsonb_typeof(p->'archived')<>'boolean')then raise exception using errcode='22023',message='Use a tag name of 1–60 characters';end if;
 if operation='create_payee_tag'then
 if p?'id' or p?'revision' or (select count(*)from household_private.payee_tags)>=200 then raise exception using errcode='22023',message='Use up to 200 payee tags';end if;
 insert into household_private.payee_tags(name)values(btrim(p->>'name'))returning id into ident;
 else
 ident:=(p->>'id')::uuid;select * into stored_tag from household_private.payee_tags where id=ident for update;
 if stored_tag.id is null or stored_tag.revision is distinct from (p->>'revision')::integer then raise exception using errcode='40001',message='Tag changed; reload before saving';end if;
 update household_private.payee_tags set name=btrim(p->>'name'),revision=revision+1,archived_at=case when coalesce((p->>'archived')::boolean,stored_tag.archived_at is not null)then coalesce(stored_tag.archived_at,now())else null end where id=ident;end if;
 insert into household_private.audit_events(actor_id,action,target_id)values(actor,operation,ident);return jsonb_build_object('id',ident);
 end if;
 if operation<>'bulk_payee_tag' or exists(select 1 from jsonb_object_keys(p)k where k not in ('tag_id','action','payees'))or coalesce(p->>'action','')not in ('add','remove')or jsonb_typeof(p->'payees') is distinct from 'array' then raise exception using errcode='22023',message='Choose a tag, action and payees';end if;
 n:=jsonb_array_length(p->'payees');if n not between 1 and 100 or n<>(select count(distinct value->>'id')from jsonb_array_elements(p->'payees'))then raise exception using errcode='22023',message='Select 1–100 unique payees';end if;
 ident:=(p->>'tag_id')::uuid;select * into stored_tag from household_private.payee_tags where id=ident for share;
 if stored_tag.id is null or (p->>'action'='add' and stored_tag.archived_at is not null)then raise exception using errcode='22023',message='Choose an active payee tag';end if;
 perform a.id from household_private.payees a join jsonb_array_elements(p->'payees')v on a.id=(v->>'id')::uuid order by a.id for update of a;
 if n<>(select count(*)from household_private.payees a join jsonb_array_elements(p->'payees')v on a.id=(v->>'id')::uuid where a.revision=(v->>'revision')::integer and (p->>'action'='remove' or a.archived_at is null))then raise exception using errcode='40001',message='Payee changed; refresh and select again';end if;
 for r in select value from jsonb_array_elements(p->'payees')loop
 if p->>'action'='add'then
 if (select count(*)from household_private.payee_tag_links where payee_id=(r->>'id')::uuid)>=30 and not exists(select 1 from household_private.payee_tag_links where payee_id=(r->>'id')::uuid and tag_id=ident)then raise exception using errcode='22023',message='Use up to 30 tags per payee';end if;
 insert into household_private.payee_tag_links values((r->>'id')::uuid,ident)on conflict do nothing;
 else delete from household_private.payee_tag_links where payee_id=(r->>'id')::uuid and tag_id=ident;end if;
 update household_private.payees set revision=revision+1 where id=(r->>'id')::uuid;
 insert into household_private.audit_events(actor_id,action,target_id)values(actor,'payee_tag_'||(p->>'action'),(r->>'id')::uuid);
 end loop;return jsonb_build_object('updated',n);
exception when unique_violation then raise exception using errcode='22023',message='A payee tag with this name already exists';
end $$;
revoke all on function household_private.payee_tag_action(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
