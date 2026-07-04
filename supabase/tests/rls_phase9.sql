-- CareBridge — Phase 9 trust tests (database level). Single DO block asserting:
--   * follow-up reminder: PAID doctor sends one (notification enqueued, manual);
--     FREE clinic is refused (Section 9); a doctor cannot send for another
--     doctor's visit; admin scope refused.
--   * AI summary input: FREE clinic refused; PAID clinic still works.
--   * prescription_templates: doctor sees/manages only OWN templates.
--   * follow_up_completed: doctor updates own visit; other doctor's row
--     untouched by the same statement (RLS row filter).
--   * carebridge_my_drug_names returns only the calling doctor's drugs.
-- Ends with a success-marker RAISE that rolls back the seed.

do $$
declare
  cp uuid := 'ca9a0000-0000-0000-0000-0000000000d9';  -- PAID clinic
  cf uuid := 'ca9b0000-0000-0000-0000-0000000000d9';  -- FREE clinic
  d1 uuid := 'd1110000-0000-0000-0000-0000000000d9';  -- paid clinic doc 1
  d2 uuid := 'd2220000-0000-0000-0000-0000000000d9';  -- paid clinic doc 2
  d3 uuid := 'd3330000-0000-0000-0000-0000000000d9';  -- free clinic doc
  p1 uuid := 'e1110000-0000-0000-0000-0000000000d9';
  v1 uuid; v2 uuid; v_cnt int; blocked boolean;
  d1_claims text := json_build_object('clinic_id',cp,'active_role','doctor','active_doctor_id',d1)::text;
  d2_claims text := json_build_object('clinic_id',cp,'active_role','doctor','active_doctor_id',d2)::text;
  d3_claims text := json_build_object('clinic_id',cf,'active_role','doctor','active_doctor_id',d3)::text;
  adm_claims text := json_build_object('clinic_id',cp,'active_role','admin','active_doctor_id',null)::text;
begin
  -- ---- seed ----
  insert into clinics (id, name, registration_number, subscription_status) values
    (cp,'Paid Clinic','REG-D9-P','paid'), (cf,'Free Clinic','REG-D9-F','free');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    (d1, cp,'Dr One','MC-D9-1','NMC','GP'),
    (d2, cp,'Dr Two','MC-D9-2','NMC','GP'),
    (d3, cf,'Dr Three','MC-D9-3','NMC','GP');
  insert into patients (id, name, phone) values (p1,'P9','+91900000d901');
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status) values
    (p1,'doctor',d1,'standing','active'),
    (p1,'doctor',d2,'standing','active'),
    (p1,'doctor',d3,'standing','active');
  insert into visits (id, patient_id, doctor_id, clinic_id, diagnosis, follow_up_date)
    values (gen_random_uuid(), p1, d1, cp, 'dx1', (now() - interval '2 days')::date)
    returning id into v1;  -- overdue follow-up, doctor 1
  insert into visits (id, patient_id, doctor_id, clinic_id, diagnosis, follow_up_date)
    values (gen_random_uuid(), p1, d2, cp, 'dx2', (now() + interval '3 days')::date)
    returning id into v2;  -- doctor 2's follow-up
  insert into prescriptions (visit_id, drug_name) values (v1, 'Amoxicillin');
  insert into prescriptions (visit_id, drug_name) values (v2, 'Cetirizine');
  delete from notifications where patient_id = p1;  -- drop trigger-enqueued rows for clean counts

  execute 'set local role authenticated';

  -- ===== Follow-up reminder: paid doctor OK; wrong doctor / admin / free refused =====
  perform set_config('request.jwt.claims', d1_claims, true);
  perform carebridge_send_followup_reminder(v1);
  -- Count as owner: the notifications feed is patient-private under RLS.
  execute 'reset role';
  select count(*) into v_cnt from notifications
    where patient_id = p1 and type = 'follow_up' and (payload->>'manual')::boolean;
  if v_cnt <> 1 then raise exception 'REMIND FAIL: manual reminder not enqueued'; end if;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', d1_claims, true);

  blocked := false;
  begin perform carebridge_send_followup_reminder(v2); exception when others then blocked := true; end;
  if not blocked then raise exception 'REMIND FAIL: doctor sent reminder for another doctor''s visit'; end if;

  perform set_config('request.jwt.claims', adm_claims, true);
  blocked := false;
  begin perform carebridge_send_followup_reminder(v1); exception when others then blocked := true; end;
  if not blocked then raise exception 'REMIND FAIL: admin scope sent a reminder (AC-9)'; end if;
  raise notice 'REMIND PASS: paid doctor sends own-visit reminders only; admin refused.';

  -- ===== Section 9 gating: FREE clinic refused for reminder AND AI summary =====
  perform set_config('request.jwt.claims', d3_claims, true);
  insert into visits (patient_id, doctor_id, clinic_id, diagnosis, follow_up_date)
    values (p1, d3, cf, 'dx3', (now() + interval '1 day')::date);
  blocked := false;
  begin
    perform carebridge_send_followup_reminder(
      (select id from visits where doctor_id = d3 limit 1));
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'GATE FAIL: free clinic sent a follow-up reminder'; end if;
  blocked := false;
  begin perform carebridge_ai_summary_input(p1); exception when others then blocked := true; end;
  if not blocked then raise exception 'GATE FAIL: free clinic got AI summary input'; end if;
  -- Paid clinic still gets the AI summary.
  perform set_config('request.jwt.claims', d1_claims, true);
  if carebridge_ai_summary_input(p1) is null then
    raise exception 'GATE FAIL: paid clinic lost AI summary';
  end if;
  raise notice 'GATE PASS: paid-tier features refused on free, allowed on paid (Section 9).';

  -- ===== Templates: own rows only =====
  insert into prescription_templates (doctor_id, name, items)
    values (d1, 'Cold pack', '[{"drug_name":"Cetirizine"}]'::jsonb);
  perform set_config('request.jwt.claims', d2_claims, true);
  select count(*) into v_cnt from prescription_templates;
  if v_cnt <> 0 then raise exception 'TEMPLATE FAIL: doctor sees another doctor''s templates'; end if;
  blocked := false;
  begin
    insert into prescription_templates (doctor_id, name) values (d1, 'forged');
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'TEMPLATE FAIL: doctor wrote a template for another doctor'; end if;
  perform set_config('request.jwt.claims', d1_claims, true);
  select count(*) into v_cnt from prescription_templates;
  if v_cnt <> 1 then raise exception 'TEMPLATE FAIL: doctor cannot read own template'; end if;
  raise notice 'TEMPLATE PASS: templates are per-doctor private.';

  -- ===== follow_up_completed: own visits only =====
  update visits set follow_up_completed = true where follow_up_date is not null;
  select count(*) into v_cnt from visits where doctor_id = d1 and follow_up_completed;
  if v_cnt <> 1 then raise exception 'DONE FAIL: doctor could not complete own follow-up'; end if;
  execute 'reset role';
  select count(*) into v_cnt from visits where doctor_id = d2 and follow_up_completed;
  if v_cnt <> 0 then raise exception 'DONE FAIL: update leaked to another doctor''s visit'; end if;
  execute 'set local role authenticated';
  raise notice 'DONE PASS: follow_up_completed updates are scoped to own visits.';

  -- ===== Autocomplete: own drug history only =====
  perform set_config('request.jwt.claims', d1_claims, true);
  select count(*) into v_cnt from carebridge_my_drug_names() where drug_name = 'Amoxicillin';
  if v_cnt <> 1 then raise exception 'DRUGS FAIL: own drug missing'; end if;
  select count(*) into v_cnt from carebridge_my_drug_names() where drug_name = 'Cetirizine';
  if v_cnt <> 0 then raise exception 'DRUGS FAIL: another doctor''s drug leaked'; end if;
  raise notice 'DRUGS PASS: autocomplete draws on the doctor''s own history only.';

  raise exception 'PHASE9_OK :: remind PASS :: gate PASS :: templates PASS :: follow-up-done PASS :: drugs PASS'
    using errcode = 'P0001';
end $$;
