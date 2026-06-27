-- CareBridge — Phase 4.5 Option A: scope_sessions + clinic GoTrue-user link.
-- Retires the self-minted HS256 scoped token. Scope is now chosen server-side
-- (after PIN) and injected into the REAL, asymmetric-signed GoTrue access token
-- by a Custom Access Token Hook (migration 0007). RLS helpers and 0003 policy
-- bodies are UNCHANGED — they still read claims via auth.jwt().
--
-- Decision (Phase 4.5): each clinic is a real GoTrue auth user (service-
-- provisioned email+password). clinics.auth_user_id links the clinic to it.

-- The GoTrue user that represents this clinic. Null until first login provisions
-- it. NOT the patient auth user (that's patients.auth_user_id) — different role.
alter table clinics
  add column if not exists auth_user_id uuid references auth.users(id);

create unique index if not exists idx_clinics_auth_user on clinics(auth_user_id)
  where auth_user_id is not null;

-- The verified scope chosen after a successful PIN. Keyed on the clinic's GoTrue
-- user id (= auth.uid()). The auth hook reads exactly this row to mint claims.
create table if not exists scope_sessions (
  auth_uid         uuid primary key references auth.users(id) on delete cascade,
  clinic_id        uuid not null references clinics(id) on delete cascade,
  active_role      text not null check (active_role in ('doctor','admin')),
  active_doctor_id uuid references doctors(id),     -- required when role='doctor' (AC-9)
  updated_at       timestamptz not null default now(),
  -- AC-9 at rest: a doctor scope must carry a doctor id; an admin scope must not.
  constraint scope_role_doctor_consistency check (
    (active_role = 'doctor' and active_doctor_id is not null) or
    (active_role = 'admin'  and active_doctor_id is null)
  )
);

alter table scope_sessions enable row level security;

-- A clinic session may READ its own scope row (handy for the app to show current
-- scope); only the service role / auth admin ever WRITES it.
drop policy if exists scope_sessions_select_self on scope_sessions;
create policy scope_sessions_select_self on scope_sessions
  for select to authenticated
  using (auth_uid = auth.uid());

grant select on scope_sessions to authenticated;
-- service_role bypasses RLS (used by the Edge Function to upsert the chosen scope).
