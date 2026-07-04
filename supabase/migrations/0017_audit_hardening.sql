-- CareBridge — Audit hardening (risk register H1-interim, H2, M3, L2).
--
-- H1 (interim): clinic login gains a weak second factor until real OTP lands
--   in Phase 11 — the caller must present the clinic's REGISTERED phone, not
--   just the (semi-public) registration number. Stored at registration.
-- H2: hospitals self-register as UNVERIFIED; the founder flips `verified` in
--   the dashboard after checking the registration. The app shows the badge.
-- M3: per-key rate limiting for the auth Edge Function (login/register
--   attempts), service-role-only table + counter function with a rolling
--   window. The Edge Function checks it before doing any work.
-- L2: booking an appointment now requires the target doctor to be active —
--   a patient can no longer point appointment rows at arbitrary/inactive ids.

-- ---- H1 interim + H2: clinic columns ----
alter table clinics add column if not exists phone text;
alter table clinics add column if not exists verified boolean not null default false;

-- Existing demo clinics stay usable and pre-verified.
update clinics set verified = true, phone = coalesce(phone, '+919000000000')
  where registration_number in ('DEMO-001','DEMO-002');

-- ---- M3: rolling-window rate limiter (service-role only) ----
create table if not exists auth_fn_attempts (
  rate_key     text primary key,          -- e.g. 'login:<ip>' / 'register:<ip>'
  window_start timestamptz not null default now(),
  attempts     int not null default 0
);
alter table auth_fn_attempts enable row level security;  -- no policies: server-only

-- Returns true when the caller is WITHIN the limit (and records the attempt).
-- 10-minute rolling window.
create or replace function carebridge_rate_ok(p_key text, p_max int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row auth_fn_attempts%rowtype;
begin
  select * into v_row from auth_fn_attempts where rate_key = p_key for update;
  if not found or v_row.window_start < now() - interval '10 minutes' then
    insert into auth_fn_attempts (rate_key, window_start, attempts)
      values (p_key, now(), 1)
    on conflict (rate_key) do update set window_start = now(), attempts = 1;
    return true;
  end if;
  if v_row.attempts >= p_max then
    return false;
  end if;
  update auth_fn_attempts set attempts = attempts + 1 where rate_key = p_key;
  return true;
end;
$$;

revoke all on function carebridge_rate_ok(text, int) from public, anon, authenticated;
grant execute on function carebridge_rate_ok(text, int) to service_role;

-- ---- L2: appointments must target an ACTIVE doctor of the named clinic ----
-- SECURITY DEFINER: a patient session has no clinic claim, so the doctors RLS
-- would hide every row and block all booking if checked directly.
create or replace function public.carebridge_doctor_active_in_clinic(p_doctor uuid, p_clinic uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from doctors d
    where d.id = p_doctor and d.clinic_id = p_clinic and d.is_active
  )
$$;

grant execute on function public.carebridge_doctor_active_in_clinic(uuid, uuid) to authenticated;

drop policy if exists appointments_insert_self on appointments;
create policy appointments_insert_self on appointments
  for insert to authenticated
  with check (
    patient_id = public.current_patient_id()
    and public.carebridge_doctor_active_in_clinic(doctor_id, clinic_id)
  );
