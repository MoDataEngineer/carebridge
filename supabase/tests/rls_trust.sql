-- CareBridge — Section 12 trust tests (b) and (c), enforced at the DATABASE level.
-- Single DO block (db query allows one command): seeds as the table owner, then
-- re-runs reads AS the 'authenticated' role with simulated D2 scoped-JWT claims,
-- asserting the RLS policies in 0003 produce exactly the right visibility, then
-- resets role and deletes the seed. Any failed assertion RAISES (command exits
-- non-zero); success exits cleanly with NOTICEs and no leftover data.
--
-- Scenario — Clinic A has doctors D1, D2:
--   P1 active grant to D1 only; P2 active grant to D2 only;
--   P3 only a REVOKED grant to D1 (must be invisible);
--   Clinic B doctor D3 has patient P4 (cross-clinic control).

do $$
declare
  sees_p1 boolean; sees_p2 boolean; sees_p3 boolean; sees_p4 boolean; total int;
  ac9_blocked boolean := false;
begin
  -- ---- Seed (as owner; RLS bypassed) ----
  insert into clinics (id, name, registration_number) values
    ('aaaaaaaa-0000-0000-0000-000000000001','Clinic A','REG-A'),
    ('bbbbbbbb-0000-0000-0000-000000000001','Clinic B','REG-B');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    ('d1111111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Dr One','MC-1','NMC','GP'),
    ('d2222222-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Dr Two','MC-2','NMC','Cardio'),
    ('d3333333-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','Dr Three','MC-3','NMC','Derm');
  insert into patients (id, name, phone) values
    ('a1111111-0000-0000-0000-000000000001','Patient One','+910000000001'),
    ('a2222222-0000-0000-0000-000000000001','Patient Two','+910000000002'),
    ('a3333333-0000-0000-0000-000000000001','Patient Three','+910000000003'),
    ('a4444444-0000-0000-0000-000000000001','Patient Four','+910000000004');
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status, revoked_at) values
    ('a1111111-0000-0000-0000-000000000001','doctor','d1111111-0000-0000-0000-000000000001','standing','active',null),
    ('a2222222-0000-0000-0000-000000000001','doctor','d2222222-0000-0000-0000-000000000001','standing','active',null),
    ('a3333333-0000-0000-0000-000000000001','doctor','d1111111-0000-0000-0000-000000000001','standing','revoked',now()),
    ('a4444444-0000-0000-0000-000000000001','doctor','d3333333-0000-0000-0000-000000000001','standing','active',null);

  -- Become the PostgREST authenticated role so RLS is actually enforced.
  execute 'set local role authenticated';

  -- ===== TEST (b): doctor-scoped D1 sees only its own granted patient =====
  perform set_config('request.jwt.claims',
    '{"clinic_id":"aaaaaaaa-0000-0000-0000-000000000001","active_role":"doctor","active_doctor_id":"d1111111-0000-0000-0000-000000000001"}', true);

  select exists(select 1 from patients where id='a1111111-0000-0000-0000-000000000001') into sees_p1;
  select exists(select 1 from patients where id='a2222222-0000-0000-0000-000000000001') into sees_p2;
  select exists(select 1 from patients where id='a3333333-0000-0000-0000-000000000001') into sees_p3;
  select count(*) into total from patients;
  if not sees_p1 then raise exception 'TEST (b) FAIL: D1 should see its own patient P1'; end if;
  if sees_p2     then raise exception 'TEST (b) FAIL: D1 must NOT see D2''s patient P2'; end if;
  if sees_p3     then raise exception 'TEST (b) FAIL: D1 must NOT see P3 (grant revoked)'; end if;
  if total <> 1  then raise exception 'TEST (b) FAIL: D1 should see exactly 1 patient, saw %', total; end if;
  raise notice 'TEST (b) PASS: doctor-scoped D1 sees only its own granted patient (P1); not P2/P3.';

  -- ===== TEST (c): admin-scoped inherits a patient if ANY clinic doctor has a grant (AC-8) =====
  perform set_config('request.jwt.claims',
    '{"clinic_id":"aaaaaaaa-0000-0000-0000-000000000001","active_role":"admin","active_doctor_id":null}', true);

  select exists(select 1 from patients where id='a1111111-0000-0000-0000-000000000001') into sees_p1;
  select exists(select 1 from patients where id='a2222222-0000-0000-0000-000000000001') into sees_p2;
  select exists(select 1 from patients where id='a3333333-0000-0000-0000-000000000001') into sees_p3;
  select exists(select 1 from patients where id='a4444444-0000-0000-0000-000000000001') into sees_p4;
  select count(*) into total from patients;
  if not sees_p1 then raise exception 'TEST (c) FAIL: admin should inherit P1 (D1 grant)'; end if;
  if not sees_p2 then raise exception 'TEST (c) FAIL: admin should inherit P2 (D2 grant)'; end if;
  if sees_p3    then raise exception 'TEST (c) FAIL: admin must NOT see P3 (grant revoked)'; end if;
  if sees_p4    then raise exception 'TEST (c) FAIL: admin must NOT see P4 (other clinic)'; end if;
  if total <> 2 then raise exception 'TEST (c) FAIL: admin should see exactly 2 patients, saw %', total; end if;
  raise notice 'TEST (c) PASS: admin-scoped inherits P1 and P2 via ANY clinic-A doctor grant; not P3/P4.';

  -- ===== AC-9: admin (no doctor identity) cannot write a visit =====
  begin
    insert into visits (patient_id, doctor_id, clinic_id, visit_date)
    values ('a1111111-0000-0000-0000-000000000001','d1111111-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', now());
  exception when others then
    ac9_blocked := true;
  end;
  if not ac9_blocked then raise exception 'AC-9 FAIL: admin session was able to write a visit'; end if;
  raise notice 'AC-9 PASS: admin-scoped session cannot write a visit (needs a doctor identity).';

  -- All assertions passed. Raise a recognizable success marker: this both makes
  -- the PASS result visible in the command output AND rolls back the whole
  -- statement, so the seed data leaves nothing behind (no manual cleanup needed).
  raise exception 'TRUST_OK :: (b) doctor isolation PASS :: (c) admin inherited-visibility PASS :: (AC-9) admin write-block PASS'
    using errcode = 'P0001';
end $$;
