-- CareBridge — Phase 3 patient self-access (RLS).
-- A patient sees/edits ONLY their own record. This is orthogonal to the
-- doctor/admin clinic scoping (0003): a patient token carries auth.uid() but no
-- clinic claim, so the clinic policies evaluate false for it, and these
-- patient policies evaluate false for clinic sessions. The two never overlap.
--
-- (Doctor access to a patient's record still flows through access_grants in
-- Phase 5 — these policies are the patient viewing their OWN data.)

-- Link a patient record to its Supabase auth user (phone-OTP signup, D3).
-- Nullable for now: real ABDM/OTP auth is Phase 11, and a record may exist
-- (phone-keyed) before an auth user is attached.
alter table patients add column if not exists auth_user_id uuid references auth.users(id);
create unique index if not exists idx_patients_auth_user on patients(auth_user_id);

-- Resolve the current patient's id from the verified auth.uid().
-- SECURITY DEFINER so the lookup itself isn't filtered by RLS (avoids recursion
-- when used inside other tables' policies).
create or replace function public.current_patient_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from patients where auth_user_id = auth.uid()
$$;

-- ---- table privileges for the patient (authenticated) ----
grant update on patients to authenticated;
grant insert on patients to authenticated;             -- bootstrap own profile row
grant select, insert on appointments to authenticated; -- view + book own appointments

-- ============================================================
-- patients — own row only (profile read/edit/bootstrap).
-- ============================================================
drop policy if exists patients_select_self on patients;
create policy patients_select_self on patients
  for select to authenticated
  using (auth_user_id = auth.uid());

drop policy if exists patients_update_self on patients;
create policy patients_update_self on patients
  for update to authenticated
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

drop policy if exists patients_insert_self on patients;
create policy patients_insert_self on patients
  for insert to authenticated
  with check (auth_user_id = auth.uid());

-- ============================================================
-- visits — patient reads own visit history (READ-ONLY: no patient insert/update).
-- ============================================================
drop policy if exists visits_select_self on visits;
create policy visits_select_self on visits
  for select to authenticated
  using (patient_id = public.current_patient_id());

-- ============================================================
-- prescriptions — patient reads prescriptions on their own visits (read-only).
-- ============================================================
drop policy if exists prescriptions_select_self on prescriptions;
create policy prescriptions_select_self on prescriptions
  for select to authenticated
  using (
    exists (
      select 1 from visits v
      where v.id = visit_id
        and v.patient_id = public.current_patient_id()
    )
  );

-- ============================================================
-- appointments — patient views and books their own.
-- ============================================================
drop policy if exists appointments_select_self on appointments;
create policy appointments_select_self on appointments
  for select to authenticated
  using (patient_id = public.current_patient_id());

drop policy if exists appointments_insert_self on appointments;
create policy appointments_insert_self on appointments
  for insert to authenticated
  with check (patient_id = public.current_patient_id());
