-- CareBridge — DEMO SEED (founder phone-testing only; not part of migrations).
-- Idempotent: fixed UUIDs + on-conflict-do-nothing, safe to re-run.
-- Login cheatsheet (demo PINs, fine to be readable here — demo data only):
--   Hospital login is by MOBILE alone (2026-07-06):
--   "Sunrise Family Clinic"  +91 9000000000  Chennai   (multi-doctor -> "Who are you?")
--     Dr Priya Sharma  PIN 1111 | Dr Arjun Mehta  PIN 2222 | Admin PIN 9999
--   "QuickCare Clinic"       +91 9000000010  Bengaluru (solo -> auto-scope, no picker)
--     Dr Ravi Kumar    PIN 1234
--   Patient Asha Rao (+919000000001) has a standing grant to Dr Priya, one visit,
--   one prescription, and a structured HbA1c report -> AI summary has real input.

insert into clinics (id, name, registration_number, admin_pin_hash, phone, verified, state, city) values
  ('11111111-1111-1111-1111-111111111101', 'Sunrise Family Clinic', 'DEMO-001', crypt('9999', gen_salt('bf')),
   '+919000000000', true, 'Tamil Nadu', 'Chennai'),
  ('11111111-1111-1111-1111-111111111102', 'QuickCare Clinic',      'DEMO-002', crypt('4321', gen_salt('bf')),
   '+919000000010', true, 'Karnataka', 'Bengaluru')
on conflict (registration_number) do nothing;

insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty, pin_hash) values
  ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111101',
   'Dr Priya Sharma', 'MC-DEMO-1', 'NMC', 'General Medicine', crypt('1111', gen_salt('bf'))),
  ('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111101',
   'Dr Arjun Mehta', 'MC-DEMO-2', 'NMC', 'Cardiology', crypt('2222', gen_salt('bf'))),
  ('22222222-2222-2222-2222-222222222203', '11111111-1111-1111-1111-111111111102',
   'Dr Ravi Kumar', 'MC-DEMO-3', 'NMC', 'Family Medicine', crypt('1234', gen_salt('bf')))
on conflict (id) do nothing;

insert into patients (id, name, phone, dob, allergies, chronic_conditions, current_medications) values
  ('33333333-3333-3333-3333-333333333301', 'Asha Rao', '+919000000001', '1978-04-12',
   '{Penicillin}', '{"Type 2 diabetes"}', '{"Metformin 500mg"}'),
  ('33333333-3333-3333-3333-333333333302', 'Bilal Khan', '+919000000002', '1990-09-30',
   '{}', '{}', '{}')
on conflict (phone) do nothing;

insert into diagnostic_partners (id, name, type, registration_number, nabl_accredited) values
  ('44444444-4444-4444-4444-444444444401', 'City Diagnostics', 'both', 'LAB-DEMO-1', true)
on conflict (registration_number) do nothing;

-- Asha -> Dr Priya: standing grant (as if Flow A already happened).
insert into access_grants (id, patient_id, granted_to_type, granted_to_id, type, status) values
  ('55555555-5555-5555-5555-555555555501', '33333333-3333-3333-3333-333333333301',
   'doctor', '22222222-2222-2222-2222-222222222201', 'standing', 'active')
on conflict (id) do nothing;

-- One past visit + prescription + follow-up, so History and the AI summary have content.
insert into visits (id, patient_id, doctor_id, clinic_id, visit_date, diagnosis, notes, follow_up_date) values
  ('66666666-6666-6666-6666-666666666601', '33333333-3333-3333-3333-333333333301',
   '22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111101',
   now() - interval '21 days', 'Type 2 diabetes — routine review',
   'Advised diet control and regular walking.', (now() - interval '7 days')::date)
on conflict (id) do nothing;

insert into prescriptions (id, visit_id, drug_name, dosage, schedule, relation_to_food, duration_days) values
  ('77777777-7777-7777-7777-777777777701', '66666666-6666-6666-6666-666666666601',
   'Metformin', '500mg', '{"morning": true, "afternoon": false, "night": true}', 'after', 30)
on conflict (id) do nothing;

-- A completed HbA1c order with a STRUCTURED report -> feeds the AI summary.
insert into test_orders (id, patient_id, doctor_id, visit_id, diagnostic_partner_id, test_type, test_name, status) values
  ('88888888-8888-8888-8888-888888888801', '33333333-3333-3333-3333-333333333301',
   '22222222-2222-2222-2222-222222222201', '66666666-6666-6666-6666-666666666601',
   '44444444-4444-4444-4444-444444444401', 'pathology', 'HbA1c', 'report_ready')
on conflict (id) do nothing;

insert into test_reports (id, test_order_id, report_type, structured_values, uploaded_by) values
  ('99999999-9999-9999-9999-999999999901', '88888888-8888-8888-8888-888888888801',
   'structured', '{"HbA1c": 7.2, "unit": "%", "reference_range": "4.0-5.6"}',
   '44444444-4444-4444-4444-444444444401')
on conflict (id) do nothing;
