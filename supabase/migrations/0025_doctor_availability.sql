-- Ayulekha — doctor weekly availability sessions + per-session capacity
-- (2026-07-07, founder request). A doctor's consultation times are a recurring
-- WEEKLY schedule: per weekday, zero or more sessions (e.g. Morning 09:00–12:00
-- cap 20, Evening 17:00–20:00 cap 15). Patients book into a session (Phase C);
-- the capacity is how many patients that session holds before it reads as
-- "fully booked" (overflow still allowed, doctor may approve — founder choice).
--
-- day_of_week uses Postgres dow: 0 = Sunday … 6 = Saturday.

create table if not exists doctor_sessions (
  id           uuid primary key default gen_random_uuid(),
  doctor_id    uuid not null references doctors(id) on delete cascade,
  day_of_week  int  not null check (day_of_week between 0 and 6),
  label        text,
  start_time   time not null,
  end_time     time not null,
  capacity     int  not null default 20 check (capacity > 0),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists idx_doctor_sessions_doctor
  on doctor_sessions(doctor_id, day_of_week);

alter table doctor_sessions enable row level security;
grant select on doctor_sessions to authenticated;

-- A clinic session (admin or the doctor themselves) can read its own doctors'
-- availability. Patients never read this table directly — Phase C exposes a
-- narrow definer RPC for booking. (No client insert/update/delete: writes go
-- through carebridge_set_doctor_sessions below.)
drop policy if exists doctor_sessions_select_clinic on doctor_sessions;
create policy doctor_sessions_select_clinic on doctor_sessions
  for select to authenticated
  using (
    exists (
      select 1 from doctors d
      where d.id = doctor_sessions.doctor_id
        and d.clinic_id = current_clinic_id()
    )
  );

-- Replace a doctor's entire weekly schedule in one call (the editor sends the
-- full set). Allowed for an ADMIN of the doctor's clinic, or the DOCTOR editing
-- their own availability (CLAUDE.md §5.2 lists both). Validates times/capacity.
create or replace function carebridge_set_doctor_sessions(p_doctor uuid, p_sessions jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clinic uuid;
  s        jsonb;
begin
  select clinic_id into v_clinic from doctors where id = p_doctor;
  if v_clinic is null then
    raise exception 'no such doctor';
  end if;
  if not (
    (current_active_role() = 'admin' and current_clinic_id() = v_clinic)
    or (current_active_role() = 'doctor' and current_active_doctor_id() = p_doctor)
  ) then
    raise exception 'setting availability requires an admin session for this clinic, or the doctor''s own session';
  end if;

  delete from doctor_sessions where doctor_id = p_doctor;

  for s in select * from jsonb_array_elements(coalesce(p_sessions, '[]'::jsonb)) loop
    if (s->>'start_time')::time >= (s->>'end_time')::time then
      raise exception 'session end time must be after its start time';
    end if;
    insert into doctor_sessions(doctor_id, day_of_week, label, start_time, end_time, capacity)
      values (
        p_doctor,
        (s->>'day_of_week')::int,
        nullif(trim(coalesce(s->>'label','')), ''),
        (s->>'start_time')::time,
        (s->>'end_time')::time,
        greatest(1, coalesce((s->>'capacity')::int, 20))
      );
  end loop;
end;
$$;

grant execute on function carebridge_set_doctor_sessions(uuid, jsonb) to authenticated;
