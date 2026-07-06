-- CareBridge — patient login support + booking directory.
--
-- Found live (Phase 10 testing): the patient flow had NO real session — the
-- Phase 1 placeholder never signed in, so patient screens rode whatever
-- session was already in the browser (e.g. a clinic login), which made
-- profile save and booking fail RLS. Fixes:
--   1. carebridge_bookable_doctors(): a NARROW directory (name/specialty/
--      clinic) for the booking dropdown. A blanket doctors SELECT policy is
--      NOT acceptable — the doctors table carries pin_hash.
--   2. carebridge_auth_user_by_email(): service-only helper so the Edge
--      Function can find an existing GoTrue user when provisioning a patient
--      login (auth schema is not reachable via PostgREST).
-- The patient_login action itself lives in the mint-scope-token function
-- (PLACEHOLDER: no OTP until Phase 11 — flagged there and in the UI).

-- ============================================================
-- 1. Public booking directory: active doctors, narrow columns only.
-- ============================================================
create or replace function carebridge_bookable_doctors()
returns table (
  doctor_id   uuid,
  doctor_name text,
  specialty   text,
  clinic_id   uuid,
  clinic_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select d.id, d.name, d.specialty, c.id, c.name
  from doctors d
  join clinics c on c.id = d.clinic_id
  where d.is_active
  order by d.name
$$;

grant execute on function carebridge_bookable_doctors() to authenticated;

-- ============================================================
-- 2. Service-only: resolve a GoTrue user id by email (provisioning repair).
-- ============================================================
create or replace function carebridge_auth_user_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from auth.users where lower(email) = lower(p_email) limit 1
$$;

revoke all on function carebridge_auth_user_by_email(text) from public, anon, authenticated;
grant execute on function carebridge_auth_user_by_email(text) to service_role;
