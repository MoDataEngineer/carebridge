-- Ayulekha — patient live queue tracker + in-app notifications (2026-07-07).
--
-- Fixes the reported gap: when a doctor checks a patient in / calls the next
-- patient, the PATIENT saw nothing. The appointments table is already realtime-
-- published and patients can read their own rows, but nothing told them their
-- token, and no notification was enqueued. This migration:
--   1. enqueues an in-app notification on check-in ("you're checked in, token N")
--      and on call-next ("it's your turn");
--   2. adds carebridge_now_serving(doctor) so a waiting patient can see the
--      doctor's current token + how many are waiting — WITHOUT seeing any other
--      patient's identity (returns aggregate numbers only, and only to a patient
--      who actually has an appointment with that doctor today).
-- The in-app feed works with no FCM config (founder decision: in-app + realtime
-- tracker now, push deferred).

-- ============================================================
-- Check-in (0019) + a "checked in" notification for the patient.
-- ============================================================
create or replace function carebridge_checkin_appointment(p_appointment uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appt  appointments%rowtype;
  v_token int;
begin
  if current_active_role() not in ('doctor', 'admin') then
    raise exception 'check-in requires a clinic session';
  end if;
  if not public.current_clinic_is_paid() then
    raise exception 'the live token tracker is a paid-tier feature (Section 9)';
  end if;

  select * into v_appt from appointments
    where id = p_appointment
      and clinic_id = current_clinic_id()
      and (current_active_role() = 'admin'
           or doctor_id = current_active_doctor_id())
    for update;
  if v_appt.id is null then
    raise exception 'no such appointment under your scope';
  end if;
  if v_appt.status <> 'scheduled' then
    raise exception 'appointment is % — only a scheduled one can be checked in', v_appt.status;
  end if;

  -- Next token for THIS doctor's day (tokens are per doctor per day).
  select coalesce(max(a.queue_position), 0) + 1 into v_token
    from appointments a
    where a.doctor_id = v_appt.doctor_id
      and a.scheduled_time >= date_trunc('day', v_appt.scheduled_time)
      and a.scheduled_time <  date_trunc('day', v_appt.scheduled_time) + interval '1 day';

  update appointments
    set status = 'waiting', queue_position = v_token
    where id = p_appointment;

  -- Tell the patient (in-app feed; delivered now).
  insert into notifications (patient_id, type, payload, scheduled_for)
    values (v_appt.patient_id, 'checked_in',
            jsonb_build_object('appointment_id', v_appt.id, 'token', v_token),
            now());

  return v_token;
end;
$$;

grant execute on function carebridge_checkin_appointment(uuid) to authenticated;

-- ============================================================
-- Call next (0019) + a "your turn" notification for the called patient.
-- ============================================================
create or replace function carebridge_call_next()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor uuid := current_active_doctor_id();
  v_next   uuid;
begin
  if current_active_role() <> 'doctor' or v_doctor is null then
    raise exception 'calling the next patient requires a doctor identity';
  end if;
  if not public.current_clinic_is_paid() then
    raise exception 'the live token tracker is a paid-tier feature (Section 9)';
  end if;

  update appointments
    set status = 'completed'
    where doctor_id = v_doctor and status = 'in_consultation';

  select a.id into v_next
    from appointments a
    where a.doctor_id = v_doctor
      and a.status = 'waiting'
      and a.scheduled_time >= date_trunc('day', now())
      and a.scheduled_time <  date_trunc('day', now()) + interval '1 day'
    order by a.queue_position
    limit 1
    for update skip locked;
  if v_next is not null then
    update appointments set status = 'in_consultation' where id = v_next;

    -- Tell that patient it's their turn (in-app feed; delivered now).
    insert into notifications (patient_id, type, payload, scheduled_for)
      select a.patient_id, 'your_turn',
             jsonb_build_object('appointment_id', a.id, 'token', a.queue_position),
             now()
      from appointments a where a.id = v_next;
  end if;
  return v_next;
end;
$$;

grant execute on function carebridge_call_next() to authenticated;

-- ============================================================
-- Now-serving: a waiting patient's live position, without exposing anyone else.
-- Returns the doctor's current in-consultation token and the waiting count for
-- TODAY — aggregate numbers only. Gated so only a patient who actually has an
-- appointment with that doctor today can read it.
-- ============================================================
create or replace function carebridge_now_serving(p_doctor uuid)
returns table (serving_token int, waiting_count int)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select a.queue_position from appointments a
       where a.doctor_id = p_doctor and a.status = 'in_consultation'
         and a.scheduled_time >= date_trunc('day', now())
         and a.scheduled_time <  date_trunc('day', now()) + interval '1 day'
       order by a.queue_position limit 1),
    (select count(*)::int from appointments a
       where a.doctor_id = p_doctor and a.status = 'waiting'
         and a.scheduled_time >= date_trunc('day', now())
         and a.scheduled_time <  date_trunc('day', now()) + interval '1 day')
  where exists (
    select 1 from appointments mine
    where mine.patient_id = current_patient_id()
      and mine.doctor_id = p_doctor
      and mine.scheduled_time >= date_trunc('day', now())
      and mine.scheduled_time <  date_trunc('day', now()) + interval '1 day'
  );
$$;

grant execute on function carebridge_now_serving(uuid) to authenticated;
