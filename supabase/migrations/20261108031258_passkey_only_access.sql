-- Require server-recorded passkey authentication for every household data/admin operation.
create or replace function household_private.member_role() returns text
language plpgsql security definer set search_path='' as $$
declare actor uuid := household_private.identity_id(); r text;
begin
 if not exists(select 1 from auth.mfa_amr_claims a
  where a.session_id=nullif(auth.jwt()->>'session_id','')::uuid and a.authentication_method='passkey') then
  raise exception using errcode='42501',message='Passkey sign-in required';
 end if;
 select m.role into r from household_private.memberships m
 where m.user_id=actor and m.status='approved' for share;
 if r is null then raise exception using errcode='42501',message='Household approval required'; end if;
 return r;
end $$;

-- Status/request access reveals only the caller's membership, not household records.
create function household_private.entry_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid := household_private.identity_id(); result jsonb;
begin
 result:=household_private.v1(operation,payload);
 if operation in ('access_state','request_access') then
  result:=result||jsonb_build_object('passkey_verified',exists(select 1 from auth.mfa_amr_claims a
   where a.session_id=nullif(auth.jwt()->>'session_id','')::uuid and a.authentication_method='passkey'));
 end if;
 return result;
end $$;
revoke all on function household_private.entry_v1(text,jsonb) from public,anon,authenticated;
grant execute on function household_private.entry_v1(text,jsonb) to authenticated;
revoke all on function household_private.v1(text,jsonb) from authenticated;
create or replace function public.household_v1(operation text,payload jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select household_private.entry_v1(operation,payload) $$;
revoke all on function public.household_v1(text,jsonb) from public,anon;
grant execute on function public.household_v1(text,jsonb) to authenticated;
notify pgrst,'reload schema';
