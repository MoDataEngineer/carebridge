-- CareBridge — Phase 10: live appointment/token tracker (Sections 5.2 + 10).
--
-- Statuses used by the queue: scheduled -> waiting (checked in, token
-- assigned) -> in_consultation -> completed; cancelled/no_show reserved.
--
-- Tier boundary (Section 9): VIEWING today's appointments is free (booking is
-- a free-tier feature, so a clinic must be able to see what was booked). The
-- TOKEN flow (check-in / call-next) is the paid "live tracker" — both
-- functions check current_clinic_is_paid(); the UI additionally gates the
-- live screen.
--
-- Privacy note (deliberate, Flow-C-style narrow columns): the queue shows the
-- patient's NAME on the clinic's own appointment rows — inherent to running a
-- booked queue — and nothing else. No history, no grant is implied or created.

-- ============================================================
-- Clinic scopes can SEE their appointments (patients already have
-- appointments_select_self from 0005; this adds the clinic side).
-- ============================================================
drop policy if exists appointments_select_clinic on appointments;
create policy appointments_select_clinic on appointments
  for select to authenticated
  using (
    (current_active_role() = 'doctor'
       and doctor_id = current_active_doctor_id())
    or
    (current_active_role() = 'admin'
       and clinic_id = current_clinic_id())
  );

-- ============================================================
-- Queue reader: today's queue, narrow columns, scope-aware.
-- Doctor scope -> own queue; admin scope -> clinic-wide (Section 5.2).
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
      and a.status not in ('cancelled')
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

-- ============================================================
-- Check-in: assign the next token for that doctor's day (paid).
-- Front desk reality: BOTH a doctor-scoped session (own rows) and an
-- admin-scoped session (any clinic row) may check a patient in — check-in is
-- operational, not clinical writing, so AC-9 does not apply.
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
  return v_token;
end;
$$;

grant execute on function carebridge_checkin_appointment(uuid) to authenticated;

-- ============================================================
-- Call next: finish the current consultation (if any) and call the
-- lowest-token waiting patient (paid). Doctor-scoped, OWN queue only —
-- who is in the room is the doctor's call, not the front desk's.
-- Returns the called appointment id (null when nobody is waiting).
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
  end if;
  return v_next;
end;
$$;

grant execute on function carebridge_call_next() to authenticated;

-- ============================================================
-- Realtime (Section 10: updates within seconds, not polling). Events are
-- change SIGNALS only — Realtime delivers rows per the SELECT policies above
-- (and patients get their own rows); the UI refetches via carebridge_live_queue().
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'appointments'
  ) then
    alter publication supabase_realtime add table appointments;
  end if;
end;
$$;
