-- CareBridge — Phase 2 RLS policy bodies (session scoping).
-- Enforces doctor-scoped vs admin-scoped visibility at the DATABASE level, keyed
-- on the D2 scoped-JWT claims read by current_clinic_id()/current_active_role()/
-- current_active_doctor_id(). App state is never trusted for access decisions.
--
-- Trust guarantees enforced here (Section 12):
--   (b) a doctor-scoped session sees ONLY patients it holds an active grant for;
--   (c) an admin-scoped session sees a patient iff ANY doctor in its clinic holds
--       an active grant (AC-8 inherited visibility) — even if the admin never
--       requested one;
--   AC-9: writing visits/prescriptions requires a specific doctor identity.

-- ============================================================
-- Table privileges for the PostgREST 'authenticated' role.
-- (RLS still filters rows; without these grants the role can't reach the table.)
-- ============================================================
grant select on patients, doctors, visits, prescriptions to authenticated;
grant insert on visits, prescriptions to authenticated;

-- ============================================================
-- Core visibility helper — the single source of truth for "can the current
-- scoped session view this patient?". SECURITY DEFINER so the grant lookup is
-- not itself blocked by RLS on access_grants/doctors.
-- ============================================================
create or replace function public.current_scope_can_view_patient(p_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    -- Doctor-scoped: an active grant must exist for THIS doctor (guarantee b).
    when current_active_role() = 'doctor' and current_active_doctor_id() is not null then
      exists (
        select 1
        from access_grants g
        where g.patient_id = p_patient
          and g.granted_to_type = 'doctor'
          and g.granted_to_id = current_active_doctor_id()
          and g.status = 'active'
          and g.revoked_at is null
          and (g.expires_at is null or g.expires_at > now())
      )
    -- Admin-scoped (AC-8): an active grant from ANY doctor in the admin's clinic
    -- is sufficient — no specific doctor_id, no separate admin consent (guarantee c).
    when current_active_role() = 'admin' and current_clinic_id() is not null then
      exists (
        select 1
        from access_grants g
        join doctors d
          on d.id = g.granted_to_id
         and d.clinic_id = current_clinic_id()
        where g.patient_id = p_patient
          and g.granted_to_type = 'doctor'
          and g.status = 'active'
          and g.revoked_at is null
          and (g.expires_at is null or g.expires_at > now())
      )
    else false
  end
$$;

-- ============================================================
-- doctors — roster visibility for the "Who are you?" picker.
-- Readable by any session (base or scoped) whose clinic_id claim matches.
-- ============================================================
drop policy if exists doctors_select_own_clinic on doctors;
create policy doctors_select_own_clinic on doctors
  for select to authenticated
  using (clinic_id = current_clinic_id());

-- ============================================================
-- patients — the core scoped read.
-- ============================================================
drop policy if exists patients_select_scoped on patients;
create policy patients_select_scoped on patients
  for select to authenticated
  using (public.current_scope_can_view_patient(id));

-- ============================================================
-- visits — read gated by patient visibility + clinic; write requires a specific
-- doctor identity writing under their own id (AC-9).
-- ============================================================
drop policy if exists visits_select_scoped on visits;
create policy visits_select_scoped on visits
  for select to authenticated
  using (
    clinic_id = current_clinic_id()
    and public.current_scope_can_view_patient(patient_id)
  );

drop policy if exists visits_insert_doctor_only on visits;
create policy visits_insert_doctor_only on visits
  for insert to authenticated
  with check (
    current_active_role() = 'doctor'
    and current_active_doctor_id() is not null
    and doctor_id = current_active_doctor_id()           -- write under own identity
    and clinic_id = current_clinic_id()
    and public.current_scope_can_view_patient(patient_id)
  );

-- ============================================================
-- prescriptions — visibility/write follow the parent visit.
-- ============================================================
drop policy if exists prescriptions_select_scoped on prescriptions;
create policy prescriptions_select_scoped on prescriptions
  for select to authenticated
  using (
    exists (
      select 1 from visits v
      where v.id = visit_id
        and v.clinic_id = current_clinic_id()
        and public.current_scope_can_view_patient(v.patient_id)
    )
  );

drop policy if exists prescriptions_insert_doctor_only on prescriptions;
create policy prescriptions_insert_doctor_only on prescriptions
  for insert to authenticated
  with check (
    current_active_role() = 'doctor'
    and current_active_doctor_id() is not null
    and exists (
      select 1 from visits v
      where v.id = visit_id
        and v.doctor_id = current_active_doctor_id()      -- only into own visits
        and v.clinic_id = current_clinic_id()
    )
  );
