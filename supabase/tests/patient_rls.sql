-- CareBridge — Phase 3 patient self-access RLS test (database level).
-- Single DO block (db query allows one command): seeds two patients tied to two
-- auth users, runs reads AS the 'authenticated' role with a simulated verified
-- token (sub = patient 1's auth uid), and asserts the patient sees ONLY their own
-- record and cannot write clinical data. Raises a success marker at the end,
-- which rolls back all seed data.
--
-- auth.uid() resolves from the 'sub' claim; current_patient_id() maps it to the
-- patient row via patients.auth_user_id.

do $$
declare
  uid1 uuid := '11111111-1111-1111-1111-111111111111';
  uid2 uuid := '22222222-2222-2222-2222-222222222222';
  sees_self boolean; sees_other boolean;
  own_visits int; own_appts int;
  visit_blocked boolean := false;
  appt_ok boolean := false;
begin
  -- Seed auth users (only id is required) + clinic/doctor for a visit.
  insert into auth.users (id) values (uid1), (uid2);
  insert into clinics (id, name, registration_number)
    values ('c0000000-0000-0000-0000-000000000001','Clinic P','REG-P');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty)
    values ('d0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','Dr P','MC-P','NMC','GP');

  insert into patients (id, name, phone, auth_user_id) values
    ('e1111111-0000-0000-0000-000000000001','Self Patient','+910000001111', uid1),
    ('e2222222-0000-0000-0000-000000000001','Other Patient','+910000002222', uid2);

  insert into visits (id, patient_id, doctor_id, clinic_id, visit_date) values
    ('11110000-0000-0000-0000-000000000001','e1111111-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001', now());
  insert into appointments (patient_id, doctor_id, clinic_id, scheduled_time) values
    ('e1111111-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001',
     'c0000000-0000-0000-0000-000000000001', now() + interval '1 day');

  -- Become the patient (verified token for uid1).
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid1, 'role','authenticated')::text, true);

  select exists(select 1 from patients where id='e1111111-0000-0000-0000-000000000001') into sees_self;
  select exists(select 1 from patients where id='e2222222-0000-0000-0000-000000000001') into sees_other;
  select count(*) into own_visits from visits;
  select count(*) into own_appts  from appointments;

  if not sees_self  then raise exception 'PATIENT RLS FAIL: cannot see own record'; end if;
  if sees_other     then raise exception 'PATIENT RLS FAIL: can see another patient''s record'; end if;
  if own_visits <> 1 then raise exception 'PATIENT RLS FAIL: should see exactly own 1 visit, saw %', own_visits; end if;
  if own_appts  <> 1 then raise exception 'PATIENT RLS FAIL: should see own 1 appointment, saw %', own_appts; end if;

  -- Read-only: a patient must NOT be able to write a visit (no doctor scope).
  begin
    insert into visits (patient_id, doctor_id, clinic_id, visit_date)
    values ('e1111111-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001',
            'c0000000-0000-0000-0000-000000000001', now());
  exception when others then
    visit_blocked := true;
  end;
  if not visit_blocked then raise exception 'PATIENT RLS FAIL: patient was able to write a visit'; end if;

  -- But a patient CAN book their own appointment.
  begin
    insert into appointments (patient_id, doctor_id, clinic_id, scheduled_time)
    values ('e1111111-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001',
            'c0000000-0000-0000-0000-000000000001', now() + interval '2 days');
    appt_ok := true;
  exception when others then
    appt_ok := false;
  end;
  if not appt_ok then raise exception 'PATIENT RLS FAIL: patient could not book own appointment'; end if;

  raise exception 'PATIENT_RLS_OK :: self-only read PASS :: visit write-block PASS :: own appointment booking PASS'
    using errcode = 'P0001';
end $$;
