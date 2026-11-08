create or replace function household_private.automation_history(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare _role text:=household_private.member_role();off integer:=coalesce((payload->>'offset')::integer,0);_source text:=coalesce(payload->>'source_key','');result jsonb;
begin
 if off not between 0 and 100000 or length(_source)>50 then raise exception using errcode='22023',message='Invalid automation activity page';end if;
 select jsonb_build_object('total',(select count(*) from household_private.automation_events e where _source='' or e.source_key=_source),'offset',off,'limit',50,'rows',coalesce((select jsonb_agg(data order by created_at desc,id desc) from (
  select e.created_at,e.id,to_jsonb(e)||jsonb_build_object('description',coalesce(t.description_override,t.description),'date',t.date,'transaction_revision',t.revision,'can_undo',e.status='applied' and e.undone_at is null and t.deleted_at is null and t.revision=e.after_revision) data
  from household_private.automation_events e join household_private.transactions t on t.id=e.transaction_id where _source='' or e.source_key=_source order by e.created_at desc,e.id desc limit 50 offset off
 ) entries),'[]'::jsonb)) into result;
 return result;
end $$;
