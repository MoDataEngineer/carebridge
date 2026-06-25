-- CareBridge — Phase 4 doctor-core RLS test (database level).
-- Single DO block (db query allows one command): seeds as the table owner, then
-- re-runs reads/writes AS the 'authenticated' role with simulated D2 scoped-JWT
-- claims, asserting the Phase 2 policies in 0003 produce exactly the right
-- behaviour for the doctor-core surface:
--   - a doctor-scoped patient SEARCH excludes other doctors' patients;
--   - an admin-scoped SEARCH sees all clinic patients with any active grant (AC-8);
--   - a visit WRITE is rejected under an admin-only scope, accepted under a
--     doctor scope writing as its own identity (AC-9).
-- The final RAISE rolls the whole block back, so the seed leaves nothing behind.
--
-- Scenario — Clinic A has doctors D1, D2:
--   P1 active grant to D1 only; P2 active grant to D2 only.

do $$
declare
  d1 uuid := 'd1111111-0000-0000-0000-000000000001';
  d2 uuid := 'd2222222-0000-0000-0000-000000000001';
  ca uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  p1 uuid := 'a1111111-0000-0000-0000-000000000001';
  p2 uuid := 'a2222222-0000-0000-0000-000000000001';
  hits int; named int;
  admin_write_blocked boolean := false;
  doctor_wrote uuid;
begin
  -- ---- Seed (as owner; RLS bypassed) ----
  insert into clinics (id, name, registration_number) values (ca,'Clinic A','REG-A');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    (d1, ca,'Dr One','MC-1','NMC','GP'),
    (d2, ca,'Dr Two','MC-2','NMC','Cardio');
  insert into patients (id, name, phone) values
    (p1,'Asha Rao','+910000000001'),
    (p2,'Bilal Khan','+910000000002');
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status, revoked_at) values
    (p1,'doctor',d1,'standing','active',null),
    (p2,'doctor',d2,'standing','active',null);

  execute 'set local role authenticated';

  -- ===== (1) doctor-scoped SEARCH excludes other doctors' patients =====
  perform set_config('request.jwt.claims',
    json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d1)::text, true);

  -- Mirrors the app's ilike search across name/phone/abha_id; RLS scopes rows.
  select count(*) into hits
    from patients
    where name ilike '%a%' or phone ilike '%a%' or abha_id ilike '%a%';
  select count(*) into named from patients where id = p2;
  if hits <> 1 then raise exception 'SEARCH (doctor) FAIL: D1 should match exactly its own patient, got %', hits; end if;
  if named <> 0 then raise exception 'SEARCH (doctor) FAIL: D1 must not see D2''s patient P2'; end if;
  raise notice 'SEARCH (doctor) PASS: D1 search returns only its own patient.';

  -- ===== (2) admin-scoped SEARCH sees all clinic patients (AC-8) =====
  perform set_config('request.jwt.claims',
    json_build_object('clinic_id',ca,'active_role','admin','active_doctor_id',null)::text, true);

  select count(*) into hits
    from patients
    where name ilike '%a%' or phone ilike '%a%' or abha_id ilike '%a%';
  if hits <> 2 then raise exception 'SEARCH (admin) FAIL: admin should match both clinic patients, got %', hits; end if;
  raise notice 'SEARCH (admin) PASS: admin search returns all clinic patients (P1 + P2).';

  -- ===== (3a) WRITE rejected under admin-only scope (AC-9) =====
  begin
    insert into visits (patient_id, doctor_id, clinic_id, visit_date)
    values (p1, d1, ca, now());
  exception when others then
    admin_write_blocked := true;
  end;
  if not admin_write_blocked then raise exception 'WRITE (admin) FAIL: admin scope was able to write a visit'; end if;
  raise notice 'WRITE (admin) PASS: admin-scoped session cannot author a visit (AC-9).';

  -- ===== (3b) WRITE accepted under doctor scope, as its own identity =====
  perform set_config('request.jwt.claims',
    json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d1)::text, true);
  insert into visits (patient_id, doctor_id, clinic_id, visit_date)
    values (p1, d1, ca, now())
    returning doctor_id into doctor_wrote;
  if doctor_wrote <> d1 then raise exception 'WRITE (doctor) FAIL: visit not written under D1 identity'; end if;
  raise notice 'WRITE (doctor) PASS: doctor scope authored a visit under its own identity.';

  raise exception 'DOCTOR_CORE_OK :: doctor-search isolation PASS :: admin-search all-clinic PASS :: admin write-block PASS :: doctor write PASS'
    using errcode = 'P0001';
end $$;
