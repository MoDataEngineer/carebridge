-- Ayulekha — booking dedupe + patient contact for the clinic (founder
-- 2026-07-18): (1) a patient could file the same session request repeatedly,
-- flooding the doctor's dashboard — now one ACTIVE booking/request per
-- patient per session per day (cancelled ones don't block a re-book);
-- (2) the clinic dashboard shows the requesting patient's phone so the
-- doctor/admin can reach them about a request.

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

  -- Founder 2026-07-18: one active booking/request per session per day.
  if exists (
    select 1 from appointments a
    where a.patient_id = v_patient
      and a.session_id = p_session
      and a.scheduled_time >= p_date::timestamptz
      and a.scheduled_time <  (p_date + 1)::timestamptz
      and a.status <> 'cancelled'
  ) then
    raise exception 'you already have a booking or request for this session — check "Your appointments" below';
  end if;

  select count(*) into v_booked from appointments a
    where a.session_id = p_session
      and a.scheduled_time >= p_date::timestamptz
      and a.scheduled_time <  (p_date + 1)::timestamptz
      and a.status <> 'cancelled';

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

-- Return type gains patient_phone -> drop + recreate.
drop function if exists carebridge_upcoming_appointments();

create or replace function carebridge_upcoming_appointments()
returns table (
  appointment_id uuid,
  patient_name   text,
  patient_phone  text,
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
    select a.id, p.name, p.phone, a.doctor_id, d.name, a.scheduled_time, s.label, a.status
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
