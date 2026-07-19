-- ============================================================
-- 0032: Two low-severity consent-flow hardenings from the 2026-07-19 review.
-- ============================================================

-- L1 — carebridge_log_view must not write an access-log row for a patient the
-- caller can't actually view. Without the guard a scoped session could forge
-- audit entries against arbitrary patient_ids, polluting the patient-facing
-- "who viewed my records" log. Gate the insert on the same visibility helper
-- the RLS policies use (covers doctor-scope and admin AC-8 inherited view).
create or replace function carebridge_log_view(p_patient uuid, p_what text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := current_active_role();
begin
  -- L1: only log a view the caller is actually authorized to make.
  if not public.current_scope_can_view_patient(p_patient) then
    raise exception 'not authorized to view this patient';
  end if;

  if v_role = 'doctor' and current_active_doctor_id() is not null then
    insert into access_logs (patient_id, accessed_by_type, accessed_by_id, what_viewed)
      values (p_patient, 'doctor', current_active_doctor_id(), p_what);
  elsif v_role = 'admin' and current_clinic_id() is not null then
    insert into access_logs (patient_id, accessed_by_type, accessed_by_id, what_viewed)
      values (p_patient, 'clinic_admin', current_clinic_id(), p_what);
  else
    raise exception 'no scoped identity to log';
  end if;
end;
$$;

-- L6 — carebridge_request_access previously inserted a fresh notification on
-- EVERY call, so a doctor could repeatedly ping the same patient even while a
-- request was already pending. Only notify when a NEW pending grant is created;
-- re-requesting an already-pending grant is now a silent no-op notification-wise.
create or replace function carebridge_request_access(p_patient uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor uuid := current_active_doctor_id();
  v_clinic uuid := current_clinic_id();
  v_grant uuid;
begin
  if current_active_role() <> 'doctor' or v_doctor is null then
    raise exception 'access requests require a specific doctor identity';
  end if;

  -- Reuse an existing pending request if present; else create one AND notify.
  select id into v_grant from access_grants
    where patient_id = p_patient and granted_to_type = 'doctor'
      and granted_to_id = v_doctor and status = 'pending';
  if v_grant is null then
    insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
      values (p_patient, 'doctor', v_doctor, 'standing', 'pending')
      returning id into v_grant;

    -- L6: notify only on a newly-created request (not on every repeat call).
    insert into notifications (patient_id, type, payload)
      values (p_patient, 'access_request',
        jsonb_build_object('grant_id', v_grant, 'doctor_id', v_doctor, 'clinic_id', v_clinic));
  end if;

  return v_grant;
end;
$$;
