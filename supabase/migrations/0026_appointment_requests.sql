-- Ayulekha — session booking + appointment approval/reject (2026-07-07).
--
-- Booking now targets a doctor_sessions slot on a chosen date:
--   within capacity  -> 'scheduled' (confirmed instantly)
--   over capacity    -> 'requested' (allowed, but the doctor may approve/reject
--                       as they wish — founder choice)
-- The doctor/admin dashboard sees TODAY + FUTURE (the old live queue is today-
-- only), and can approve a pending request or reject any upcoming appointment
-- (e.g. emergency unavailability), notifying the patient.

alter table appointments
  add column if not exists session_id uuid references doctor_sessions(id);

-- ============================================================
-- Patient-facing: the doctor's sessions for a given date's weekday, with how
-- many are already booked vs capacity. Patients can't read doctor_sessions
-- directly (definer). Non-sensitive booking info — callable by any patient.
-- ============================================================
create or replace function carebridge_available_sessions(p_doctor uuid, p_date date)
returns table (
  session_id  uuid,
  label       text,
  start_time  time,
  end_time    time,
  capacity    int,
  booked      int
)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.label, s.start_time, s.end_time, s.capacity,
         (select count(*)::int from appointments a
            where a.session_id = s.id
              and a.scheduled_time >= p_date::timestamptz
              and a.scheduled_time <  (p_date + 1)::timestamptz
              and a.status <> 'cancelled') as booked
  from doctor_sessions s
  where s.doctor_id = p_doctor
    and s.is_active
    and s.day_of_week = extract(dow from p_date)::int
  order by s.start_time;
$$;

grant execute on function carebridge_available_sessions(uuid, date) to authenticated;

-- ============================================================
-- Patient-facing: request an appointment into a session on a date. Within
-- capacity confirms ('scheduled'); over capacity is 'requested' (pending the
-- doctor). Returns the resulting status + counts so the app can message it.
-- ============================================================
create or replace function carebridge_request_appointment(
  p_session uuid,
  p_date    date
)
returns table (appointment_id uuid, status text, booked int, capacity int)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := current_patient_id();
  v_sess    doctor_sessions%rowtype;
  v_booked  int;
  v_status  text;
  v_when    timestamptz;
  v_appt    uuid;
begin
  if v_patient is null then
    raise exception 'a patient session is required to book';
  end if;
  select * into v_sess from doctor_sessions where id = p_session and is_active;
  if v_sess.id is null then
    raise exception 'no such session';
  end if;
  if v_sess.day_of_week <> extract(dow from p_date)::int then
    raise exception 'that session is not offered on the chosen day';
  end if;
  if p_date < now()::date then
    raise exception 'choose today or a future date';
  end if;

  select count(*) into v_booked from appointments a
    where a.session_id = p_session
      and a.scheduled_time >= p_date::timestamptz
      and a.scheduled_time <  (p_date + 1)::timestamptz
      and a.status <> 'cancelled';

  -- Within capacity confirms; overflow waits for the doctor.
  v_status := case when v_booked < v_sess.capacity then 'scheduled' else 'requested' end;
  v_when := p_date::timestamptz + v_sess.start_time;

  insert into appointments (patient_id, doctor_id, clinic_id, scheduled_time,
                            status, session_id)
    select v_patient, v_sess.doctor_id, d.clinic_id, v_when, v_status, p_session
    from doctors d where d.id = v_sess.doctor_id
    returning id into v_appt;

  return query select v_appt, v_status, v_booked, v_sess.capacity;
end;
$$;

grant execute on function carebridge_request_appointment(uuid, date) to authenticated;

-- ============================================================
-- Clinic-facing: upcoming appointments (TODAY + FUTURE) for the active scope —
-- doctor = own, admin = clinic-wide. Fixes "future days not visible".
-- ============================================================
create or replace function carebridge_upcoming_appointments()
returns table (
  appointment_id uuid,
  patient_name   text,
  doctor_id      uuid,
  doctor_name    text,
  scheduled_time timestamptz,
  session_label  text,
  status         text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if current_active_role() not in ('doctor', 'admin') then
    raise exception 'appointments are only available to a clinic session';
  end if;
  return query
    select a.id, p.name, a.doctor_id, d.name, a.scheduled_time, s.label, a.status
    from appointments a
    join patients p on p.id = a.patient_id
    join doctors  d on d.id = a.doctor_id
    left join doctor_sessions s on s.id = a.session_id
    where a.clinic_id = current_clinic_id()
      and (current_active_role() = 'admin' or a.doctor_id = current_active_doctor_id())
      and a.scheduled_time >= date_trunc('day', now())
      and a.status <> 'cancelled'
    order by a.scheduled_time,
      case a.status when 'requested' then 0 else 1 end;
end;
$$;

grant execute on function carebridge_upcoming_appointments() to authenticated;

-- ============================================================
-- Approve a pending request (requested -> scheduled). Doctor = own, admin = any
-- in clinic. Notifies the patient.
-- ============================================================
create or replace function carebridge_approve_appointment(p_appointment uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_appt appointments%rowtype;
begin
  if current_active_role() not in ('doctor', 'admin') then
    raise exception 'approving requires a clinic session';
  end if;
  select * into v_appt from appointments
    where id = p_appointment
      and clinic_id = current_clinic_id()
      and (current_active_role() = 'admin' or doctor_id = current_active_doctor_id())
    for update;
  if v_appt.id is null then
    raise exception 'no such appointment under your scope';
  end if;
  if v_appt.status <> 'requested' then
    raise exception 'only a pending request can be approved';
  end if;
  update appointments set status = 'scheduled' where id = p_appointment;
  insert into notifications (patient_id, type, payload, scheduled_for)
    values (v_appt.patient_id, 'appointment_approved',
            jsonb_build_object('appointment_id', v_appt.id,
                               'scheduled_time', v_appt.scheduled_time),
            now());
end;
$$;

grant execute on function carebridge_approve_appointment(uuid) to authenticated;

-- ============================================================
-- Reject / cancel any upcoming appointment (e.g. emergency). Doctor = own,
-- admin = any in clinic. Notifies the patient with the reason.
-- ============================================================
create or replace function carebridge_reject_appointment(p_appointment uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_appt appointments%rowtype;
begin
  if current_active_role() not in ('doctor', 'admin') then
    raise exception 'rejecting requires a clinic session';
  end if;
  select * into v_appt from appointments
    where id = p_appointment
      and clinic_id = current_clinic_id()
      and (current_active_role() = 'admin' or doctor_id = current_active_doctor_id())
    for update;
  if v_appt.id is null then
    raise exception 'no such appointment under your scope';
  end if;
  if v_appt.status in ('completed', 'cancelled') then
    raise exception 'that appointment is already %', v_appt.status;
  end if;
  update appointments set status = 'cancelled' where id = p_appointment;
  insert into notifications (patient_id, type, payload, scheduled_for)
    values (v_appt.patient_id, 'appointment_rejected',
            jsonb_build_object('appointment_id', v_appt.id,
                               'reason', nullif(trim(coalesce(p_reason, '')), '')),
            now());
end;
$$;

grant execute on function carebridge_reject_appointment(uuid, text) to authenticated;

-- ============================================================
-- Live token queue (0019/0024) now EXCLUDES pending requests — they belong in
-- the appointments dashboard, not the token queue. Recreated with that filter.
-- ============================================================
create or replace function carebridge_live_queue()
returns table (
  appointment_id uuid,
  patient_name   text,
  scheduled_time timestamptz,
  status         text,
  queue_position int,
  doctor_id      uuid,
  doctor_name    text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if current_active_role() not in ('doctor', 'admin') then
    raise exception 'the queue is only available to a clinic session';
  end if;
  return query
    select a.id, p.name, a.scheduled_time, a.status, a.queue_position,
           a.doctor_id, d.name
    from appointments a
    join patients p on p.id = a.patient_id
    join doctors  d on d.id = a.doctor_id
    where a.clinic_id = current_clinic_id()
      and (current_active_role() = 'admin'
           or a.doctor_id = current_active_doctor_id())
      and a.scheduled_time >= date_trunc('day', now())
      and a.scheduled_time <  date_trunc('day', now()) + interval '1 day'
      and a.status in ('scheduled', 'waiting', 'in_consultation', 'completed')
    order by
      case a.status when 'in_consultation' then 0
                    when 'waiting'         then 1
                    when 'scheduled'       then 2
                    else 3 end,
      a.queue_position nulls last,
      a.scheduled_time;
end;
$$;

grant execute on function carebridge_live_queue() to authenticated;
