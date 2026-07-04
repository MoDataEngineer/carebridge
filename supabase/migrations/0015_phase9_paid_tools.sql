-- CareBridge — Phase 9: follow-up tracker, prescription templates, and
-- subscription gating (Sections 5.2 + 9).
--
-- Paid-tier boundary (Section 9), enforced at the DB for the server-side
-- features: AI summary input and one-tap follow-up reminders check
-- current_clinic_is_paid(). Templates/autocomplete/voice are client tools —
-- their DATA access is still RLS-scoped here, and the UI gates the features.
-- clinics.subscription_status stays a manually-set flag for MVP (founder can
-- flip it in the dashboard; the Upgrade screen is a stub).

-- ============================================================
-- Subscription helper — is the CURRENT clinic scope on the paid tier?
-- ============================================================
create or replace function public.current_clinic_is_paid()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select subscription_status = 'paid' from clinics where id = current_clinic_id()),
    false)
$$;

-- ============================================================
-- prescription_templates — a doctor's saved prescription sets (paid tool).
-- items: [{drug_name, dosage, schedule, relation_to_food, duration_days}]
-- ============================================================
create table if not exists prescription_templates (
  id         uuid primary key default gen_random_uuid(),
  doctor_id  uuid not null references doctors(id) on delete cascade,
  name       text not null,
  items      jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_rx_templates_doctor on prescription_templates(doctor_id);

alter table prescription_templates enable row level security;
grant select, insert, delete on prescription_templates to authenticated;

-- A doctor-scoped session manages ONLY its own templates.
drop policy if exists rx_templates_own on prescription_templates;
create policy rx_templates_own on prescription_templates
  for all to authenticated
  using (doctor_id = current_active_doctor_id())
  with check (doctor_id = current_active_doctor_id());

-- ============================================================
-- Follow-up tracker: a doctor updates follow_up_completed on OWN visits.
-- (Select already rides visits_select_scoped from 0003.)
-- ============================================================
grant update (follow_up_completed) on visits to authenticated;

drop policy if exists visits_update_followup_own on visits;
create policy visits_update_followup_own on visits
  for update to authenticated
  using (
    current_active_role() = 'doctor'
    and doctor_id = current_active_doctor_id()
  )
  with check (
    current_active_role() = 'doctor'
    and doctor_id = current_active_doctor_id()
  );

-- ============================================================
-- One-tap follow-up reminder (paid): doctor sends "you're due" NOW for one of
-- their own visits. Server-side insert (notifications are client-write-locked).
-- ============================================================
create or replace function carebridge_send_followup_reminder(p_visit uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor uuid := current_active_doctor_id();
  v_visit  visits%rowtype;
begin
  if current_active_role() <> 'doctor' or v_doctor is null then
    raise exception 'sending a follow-up reminder requires a doctor identity';
  end if;
  if not public.current_clinic_is_paid() then
    raise exception 'follow-up reminders are a paid-tier feature (Section 9)';
  end if;

  select * into v_visit from visits where id = p_visit and doctor_id = v_doctor;
  if v_visit.id is null then
    raise exception 'no such visit under your identity';
  end if;
  if v_visit.follow_up_date is null or v_visit.follow_up_completed then
    raise exception 'visit has no open follow-up';
  end if;

  insert into notifications (patient_id, type, payload, scheduled_for)
    values (v_visit.patient_id, 'follow_up',
            jsonb_build_object('visit_id', v_visit.id,
                               'follow_up_date', v_visit.follow_up_date,
                               'manual', true),
            now());
end;
$$;

grant execute on function carebridge_send_followup_reminder(uuid) to authenticated;

-- ============================================================
-- Autocomplete source: distinct drug names this doctor has prescribed before.
-- (Definer fn keeps it one cheap call; scoped to the doctor's own history.)
-- ============================================================
create or replace function carebridge_my_drug_names()
returns table (drug_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_active_role() <> 'doctor' or current_active_doctor_id() is null then
    return;
  end if;
  return query
    select distinct rx.drug_name
    from prescriptions rx
    join visits v on v.id = rx.visit_id
    where v.doctor_id = current_active_doctor_id()
    order by rx.drug_name
    limit 200;
end;
$$;

grant execute on function carebridge_my_drug_names() to authenticated;

-- ============================================================
-- Gate the AI summary (paid, Section 9): recreate the Phase 7 input function
-- with the subscription check added. Body otherwise unchanged from 0012.
-- ============================================================
create or replace function carebridge_ai_summary_input(p_patient uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role   text := current_active_role();
  v_banner jsonb;
  v_visits jsonb;
  v_tests  jsonb;
begin
  if v_role not in ('doctor', 'admin') then
    raise exception 'AI summary is only available to a clinic session';
  end if;
  -- Phase 9: AI summary is a paid-tier feature (Section 9).
  if not public.current_clinic_is_paid() then
    raise exception 'AI summary is a paid-tier feature (Section 9)';
  end if;
  if not public.current_scope_can_view_patient(p_patient) then
    raise exception 'no active grant to view this patient';
  end if;

  select jsonb_build_object(
           'allergies',           to_jsonb(p.allergies),
           'chronic_conditions',  to_jsonb(p.chronic_conditions),
           'current_medications', to_jsonb(p.current_medications))
    into v_banner
    from patients p where p.id = p_patient;
  if v_banner is null then
    raise exception 'unknown patient';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'visit_id',            v.id,
           'date',                to_char(v.visit_date, 'YYYY-MM-DD'),
           'diagnosis',           v.diagnosis,
           'follow_up_date',      to_char(v.follow_up_date, 'YYYY-MM-DD'),
           'follow_up_completed', v.follow_up_completed,
           'prescriptions',       coalesce((
             select jsonb_agg(jsonb_build_object(
                      'drug',          rx.drug_name,
                      'dosage',        rx.dosage,
                      'schedule',      rx.schedule,
                      'duration_days', rx.duration_days))
             from prescriptions rx where rx.visit_id = v.id), '[]'::jsonb)
         ) order by v.visit_date), '[]'::jsonb)
    into v_visits
    from visits v where v.patient_id = p_patient;

  select coalesce(jsonb_agg(jsonb_build_object(
           'test_order_id',     o.id,
           'test_name',         o.test_name,
           'test_type',         o.test_type,
           'status',            o.status,
           'reported_at',       to_char(r.uploaded_at, 'YYYY-MM-DD'),
           'structured_values', r.structured_values
         ) order by o.created_at), '[]'::jsonb)
    into v_tests
    from test_orders o
    left join test_reports r
      on r.test_order_id = o.id and r.report_type = 'structured'
    where o.patient_id = p_patient and o.status <> 'cancelled';

  if v_role = 'doctor' and current_active_doctor_id() is not null then
    insert into access_logs (patient_id, accessed_by_type, accessed_by_id, what_viewed)
      values (p_patient, 'doctor', current_active_doctor_id(), 'AI summary');
  elsif v_role = 'admin' and current_clinic_id() is not null then
    insert into access_logs (patient_id, accessed_by_type, accessed_by_id, what_viewed)
      values (p_patient, 'clinic_admin', current_clinic_id(), 'AI summary');
  else
    raise exception 'no scoped identity to log';
  end if;

  return jsonb_build_object(
    'patient_id', p_patient,
    'banner',     v_banner,
    'visits',     v_visits,
    'tests',      v_tests);
end;
$$;
