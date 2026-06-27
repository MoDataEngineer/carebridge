-- CareBridge — Phase 4.5 Option A: Custom Access Token Hook.
-- Registered with GoTrue (Dashboard → Authentication → Hooks → Customize Access
-- Token). GoTrue calls this function every time it issues/refreshes an access
-- token, passing {user_id, claims, ...}. We read the caller's scope_sessions row
-- and inject clinic_id / active_role / active_doctor_id into the claims. Supabase
-- then signs the token with the ASYMMETRIC key — no self-minting anywhere.
--
-- RLS reads these claims via auth.jwt() exactly as in Phase 2 (helpers unchanged).
-- Because the claims now ride a project-signed token, a client cannot forge scope.

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (event ->> 'user_id')::uuid;
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_scope  scope_sessions%rowtype;
begin
  select * into v_scope from scope_sessions where auth_uid = v_uid;

  if found then
    -- Inject the verified scope. RLS helpers read these top-level claims.
    v_claims := v_claims
      || jsonb_build_object('clinic_id', v_scope.clinic_id::text)
      || jsonb_build_object('active_role', v_scope.active_role)
      || jsonb_build_object(
           'active_doctor_id',
           case when v_scope.active_doctor_id is null then null
                else v_scope.active_doctor_id::text end
         );
  else
    -- No scope chosen yet (between login and PIN): explicitly null so a stale
    -- claim can never linger across a scope switch / sign-out.
    v_claims := v_claims
      || jsonb_build_object('clinic_id', null)
      || jsonb_build_object('active_role', null)
      || jsonb_build_object('active_doctor_id', null);
  end if;

  return jsonb_set(event, '{claims}', v_claims);
end;
$$;

-- The auth hook runs as the supabase_auth_admin role — grant it precisely what it
-- needs and nothing else; deny everyone else so the hook can't be called via API.
grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;

grant select on scope_sessions to supabase_auth_admin;
drop policy if exists scope_sessions_auth_admin_read on scope_sessions;
create policy scope_sessions_auth_admin_read on scope_sessions
  for select to supabase_auth_admin
  using (true);
