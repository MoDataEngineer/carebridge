-- CareBridge — Phase 5: access-grant / consent flows (Section 7). The core trust
-- mechanism, enforced at the DATABASE level.
--
-- Grants are NEVER written directly by a client — every mutation goes through a
-- SECURITY DEFINER function that authorizes off the verified scope claims
-- (current_patient_id() for patients, current_active_doctor_id() for doctors).
-- RLS lets a patient READ + REVOKE their own grants and read their own access
-- log; doctors READ grants made to them. The Phase 2 visibility helper
-- (current_scope_can_view_patient) is unchanged — these flows just create the
-- rows it checks.
--
-- Flow A (in-person): patient generates a short-lived consent code; the doctor
--   redeems it → standing grant created immediately (D4).
-- Flow B (remote): doctor requests access → pending grant + patient notification
--   → patient approves/denies → grant goes active only on approval.

-- ============================================================
-- Flow A — short-lived consent codes
-- ============================================================
create table if not exists consent_codes (
  id                uuid primary key default gen_random_uuid(),
  patient_id        uuid not null references patients(id) on delete cascade,
  code              text not null unique default encode(gen_random_bytes(8), 'hex'),
  created_at        timestamptz not null default now(),
  expires_at        timestamptz not null default now() + interval '10 minutes',
  redeemed_at       timestamptz,
  redeemed_by_doctor uuid references doctors(id)
);
create index if not exists idx_consent_codes_code on consent_codes(code);

alter table consent_codes enable row level security;

-- A patient may read only their own codes (to render the QR/code). Inserts and
-- redemption go through the functions below, not direct DML.
drop policy if exists consent_codes_select_self on consent_codes;
create policy consent_codes_select_self on consent_codes
  for select to authenticated
  using (patient_id = current_patient_id());

grant select on consent_codes to authenticated;

-- ============================================================
-- RLS reads for grants + logs (writes are function-only)
-- ============================================================
-- access_grants: a patient sees their own grants ("Doctors with access"); a
-- doctor-scoped session sees grants made to that doctor.
drop policy if exists access_grants_select_patient on access_grants;
create policy access_grants_select_patient on access_grants
  for select to authenticated
  using (patient_id = current_patient_id());

drop policy if exists access_grants_select_doctor on access_grants;
create policy access_grants_select_doctor on access_grants
  for select to authenticated
  using (
    granted_to_type = 'doctor'
    and granted_to_id = current_active_doctor_id()
  );

grant select on access_grants to authenticated;

-- access_logs: a patient reads their own access history ("Who viewed my records").
drop policy if exists access_logs_select_self on access_logs;
create policy access_logs_select_self on access_logs
  for select to authenticated
  using (patient_id = current_patient_id());

grant select on access_logs to authenticated;

-- notifications: a patient reads their own (Flow B approval prompts live here).
drop policy if exists notifications_select_self on notifications;
create policy notifications_select_self on notifications
  for select to authenticated
  using (patient_id = current_patient_id());

grant select on notifications to authenticated;

-- ============================================================
-- Functions — all SECURITY DEFINER, authorize off verified scope claims.
-- ============================================================

-- Patient: mint a short-lived consent code (Flow A).
create or replace function carebridge_create_consent_code()
returns table (code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := current_patient_id();
  v_code text;
  v_exp  timestamptz;
begin
  if v_patient is null then
    raise exception 'not a patient session';
  end if;
  insert into consent_codes (patient_id)
    values (v_patient)
    returning consent_codes.code, consent_codes.expires_at into v_code, v_exp;
  return query select v_code, v_exp;
end;
$$;

-- Doctor: redeem a consent code → standing grant (Flow A). Idempotent if an
-- active grant already exists. Logs the consent event.
create or replace function carebridge_redeem_consent_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor uuid := current_active_doctor_id();
  v_patient uuid;
begin
  -- Only a specific doctor identity can take consent (mirrors AC-9 accountability).
  if current_active_role() <> 'doctor' or v_doctor is null then
    raise exception 'consent must be redeemed under a specific doctor identity';
  end if;

  select patient_id into v_patient
  from consent_codes
  where code = p_code and redeemed_at is null and expires_at > now()
  for update;

  if v_patient is null then
    raise exception 'invalid or expired consent code';
  end if;

  -- Create the standing grant unless one is already active for this doctor.
  if not exists (
    select 1 from access_grants
    where patient_id = v_patient and granted_to_type = 'doctor'
      and granted_to_id = v_doctor and status = 'active' and revoked_at is null
  ) then
    insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
      values (v_patient, 'doctor', v_doctor, 'standing', 'active');
  end if;

  update consent_codes
    set redeemed_at = now(), redeemed_by_doctor = v_doctor
    where code = p_code;

  insert into access_logs (patient_id, accessed_by_type, accessed_by_id, what_viewed)
    values (v_patient, 'doctor', v_doctor, 'consent granted (Flow A in-person)');

  return v_patient;
end;
$$;

-- Doctor: request access to a patient (Flow B) → pending grant + notification.
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

  -- Reuse an existing pending request if present; else create one.
  select id into v_grant from access_grants
    where patient_id = p_patient and granted_to_type = 'doctor'
      and granted_to_id = v_doctor and status = 'pending';
  if v_grant is null then
    insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
      values (p_patient, 'doctor', v_doctor, 'standing', 'pending')
      returning id into v_grant;
  end if;

  insert into notifications (patient_id, type, payload)
    values (p_patient, 'access_request',
      jsonb_build_object('grant_id', v_grant, 'doctor_id', v_doctor, 'clinic_id', v_clinic));

  return v_grant;
end;
$$;

-- Patient: approve or deny a pending request (Flow B).
create or replace function carebridge_respond_access(p_grant uuid, p_approve boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := current_patient_id();
  v_found uuid;
begin
  if v_patient is null then
    raise exception 'not a patient session';
  end if;

  select id into v_found from access_grants
    where id = p_grant and patient_id = v_patient and status = 'pending'
    for update;
  if v_found is null then
    raise exception 'no pending request for this patient';
  end if;

  if p_approve then
    update access_grants set status = 'active', granted_at = now() where id = p_grant;
    return 'active';
  else
    update access_grants set status = 'revoked', revoked_at = now() where id = p_grant;
    return 'denied';
  end if;
end;
$$;

-- Patient: one-tap revoke an active grant ("Doctors with access").
create or replace function carebridge_revoke_grant(p_grant uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := current_patient_id();
  v_found uuid;
begin
  if v_patient is null then
    raise exception 'not a patient session';
  end if;

  update access_grants
    set revoked_at = now(), status = 'revoked'
    where id = p_grant and patient_id = v_patient and status = 'active'
    returning id into v_found;
  if v_found is null then
    raise exception 'no active grant to revoke for this patient';
  end if;
end;
$$;

-- Any scoped viewer: record an access-log entry when a record is opened. The
-- accessor type/id are derived from the verified scope (doctor vs clinic_admin).
create or replace function carebridge_log_view(p_patient uuid, p_what text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := current_active_role();
begin
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

-- Callable by client sessions; each function authorizes off scope internally.
grant execute on function carebridge_create_consent_code()            to authenticated;
grant execute on function carebridge_redeem_consent_code(text)        to authenticated;
grant execute on function carebridge_request_access(uuid)             to authenticated;
grant execute on function carebridge_respond_access(uuid, boolean)    to authenticated;
grant execute on function carebridge_revoke_grant(uuid)               to authenticated;
grant execute on function carebridge_log_view(uuid, text)             to authenticated;
