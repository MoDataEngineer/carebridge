-- CareBridge — Phase 4.5: clinic GoTrue password stored ENCRYPTED in Supabase Vault.
-- Decision (Phase 4.5): each clinic's service-provisioned GoTrue login password is
-- persisted, encrypted at rest (pgsodium/Vault), and readable ONLY by the service
-- role via the SECURITY DEFINER RPCs below. It is never returned to a client, never
-- exposed to anon/authenticated, and never logged. The Edge Function reads it only
-- transiently to sign the clinic in.
--
-- These RPCs are the ONLY sanctioned path to the secret. EXECUTE is revoked from
-- every client role and granted solely to service_role.

-- Write (create-or-rotate) a clinic's login password into Vault, keyed by a stable
-- per-clinic secret name. Idempotent.
create or replace function carebridge_set_clinic_secret(p_clinic_id uuid, p_secret text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := 'clinic_password:' || p_clinic_id::text;
  v_id   uuid;
begin
  select id into v_id from vault.secrets where name = v_name;
  if v_id is null then
    perform vault.create_secret(p_secret, v_name, 'CareBridge clinic GoTrue login password');
  else
    perform vault.update_secret(v_id, p_secret);
  end if;
end;
$$;

-- Read a clinic's decrypted login password. Service-role only.
create or replace function carebridge_get_clinic_secret(p_clinic_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = 'clinic_password:' || p_clinic_id::text
$$;

-- Lock down: no client role may ever call these.
revoke all on function carebridge_set_clinic_secret(uuid, text) from public, anon, authenticated;
revoke all on function carebridge_get_clinic_secret(uuid)       from public, anon, authenticated;
grant execute on function carebridge_set_clinic_secret(uuid, text) to service_role;
grant execute on function carebridge_get_clinic_secret(uuid)       to service_role;
