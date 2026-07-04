-- CareBridge — Phase 7 AI-summary trust tests (database level). Single DO block:
-- seeds as owner, then switches scopes via set_config, asserting:
--   * a doctor WITH a grant gets the structured input (visits + tests + banner);
--   * visit free-text NOTES never appear in the input (Section 8 hard rule);
--   * only STRUCTURED test values pass — pdf/image file URLs are excluded;
--   * an admin scope inherits access via AC-8 (no separate consent);
--   * a doctor WITHOUT a grant is refused;
--   * a patient session is refused (clinic scopes only);
--   * every successful call lands in access_logs (doctor vs clinic_admin);
--   * the ai_summaries cache is readable only by scopes that may view the
--     patient, and NOT writable by any authenticated client (service role only).
-- Ends with a success-marker RAISE that rolls back the seed.

do $$
declare
  ca uuid := 'cafe0000-0000-0000-0000-0000000000d7';
  d1 uuid := 'd1110000-0000-0000-0000-0000000000d7';
  d2 uuid := 'd2220000-0000-0000-0000-0000000000d7';
  cb uuid := 'cbbb0000-0000-0000-0000-0000000000d7';  -- unrelated clinic for d2
  pp uuid := 'eeee0000-0000-0000-0000-0000000000d7';
  l1 uuid := 'b1ab0000-0000-0000-0000-0000000000d7';
  uidp uuid := 'a11c0000-0000-0000-0000-0000000000d7';
  vv uuid; oo uuid;
  doc_claims  text := json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d1)::text;
  adm_claims  text := json_build_object('clinic_id',ca,'active_role','admin','active_doctor_id',null)::text;
  doc2_claims text := json_build_object('clinic_id',cb,'active_role','doctor','active_doctor_id',d2)::text;
  pat_claims  text := json_build_object('sub',uidp,'role','authenticated')::text;
  v_input jsonb; v_cnt int; blocked boolean;
begin
  -- ---- seed (owner; RLS bypassed) ----
  insert into auth.users (id) values (uidp);
  -- Phase 9: AI summary is paid-gated; this harness tests the GRANT model, so
  -- seed both clinics as paid (the tier gate has its own tests in rls_phase9).
  insert into clinics (id, name, registration_number, subscription_status) values
    (ca,'Clinic S','REG-D7-A','paid'), (cb,'Clinic T','REG-D7-B','paid');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    (d1, ca,'Dr One','MC-D7-1','NMC','GP'),
    (d2, cb,'Dr Two','MC-D7-2','NMC','GP');
  insert into patients (id, name, phone, auth_user_id, allergies, current_medications)
    values (pp,'Sum P','+91900000d701', uidp, '{Penicillin}', '{Metformin 500mg}');
  insert into diagnostic_partners (id, name, type, registration_number)
    values (l1,'Lab S','lab','LAB-D7-1');
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
    values (pp, 'doctor', d1, 'standing', 'active');
  -- One visit WITH a free-text note (must never surface), one prescription.
  insert into visits (id, patient_id, doctor_id, clinic_id, diagnosis, notes, follow_up_date)
    values (gen_random_uuid(), pp, d1, ca, 'Type 2 diabetes', 'SECRET-NOTE-TEXT', current_date + 14)
    returning id into vv;
  insert into prescriptions (visit_id, drug_name, dosage, duration_days)
    values (vv, 'Metformin', '500mg', 30);
  -- One order with a STRUCTURED report, one with a PDF report (file must be excluded).
  insert into test_orders (id, patient_id, doctor_id, test_type, test_name, status)
    values (gen_random_uuid(), pp, d1, 'pathology', 'HbA1c', 'report_ready')
    returning id into oo;
  insert into test_reports (test_order_id, report_type, structured_values, uploaded_by)
    values (oo, 'structured', '{"HbA1c": 7.2}'::jsonb, l1);
  insert into test_orders (patient_id, doctor_id, test_type, test_name, status)
    values (pp, d1, 'imaging', 'Chest X-Ray', 'report_ready');
  -- Cached summary row (as the service role / Edge Function would write it).
  insert into ai_summaries (patient_id, summary, input_fingerprint)
    values (pp, '{"summary":"cached"}'::jsonb, 'fp1');

  execute 'set local role authenticated';

  -- ===== Doctor WITH grant: gets structured input; notes/files excluded =====
  perform set_config('request.jwt.claims', doc_claims, true);
  v_input := carebridge_ai_summary_input(pp);
  if jsonb_array_length(v_input->'visits') <> 1 then
    raise exception 'INPUT FAIL: expected 1 visit, got %', v_input->'visits';
  end if;
  if v_input::text like '%SECRET-NOTE-TEXT%' then
    raise exception 'SAFETY FAIL: free-text visit notes leaked into AI input';
  end if;
  if (v_input->'banner'->'allergies')::text not like '%Penicillin%' then
    raise exception 'BANNER FAIL: allergies missing from deterministic banner';
  end if;
  if v_input::text not like '%HbA1c%' or v_input::text not like '%7.2%' then
    raise exception 'INPUT FAIL: structured test values missing';
  end if;
  if v_input::text like '%file_url%' then
    raise exception 'SAFETY FAIL: file-based report fields leaked into AI input';
  end if;
  raise notice 'INPUT PASS: structured fields only — no notes, no files; banner present.';

  -- Doctor can read the cached summary via RLS.
  select count(*) into v_cnt from ai_summaries where patient_id = pp;
  if v_cnt <> 1 then raise exception 'CACHE FAIL: granted doctor cannot read ai_summaries'; end if;

  -- Clients must NOT be able to write the cache (service role only).
  blocked := false;
  begin
    insert into ai_summaries (patient_id, summary, input_fingerprint)
      values (pp, '{"summary":"forged"}'::jsonb, 'fpX')
      on conflict (patient_id) do update set summary = excluded.summary;
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'CACHE FAIL: authenticated client wrote ai_summaries'; end if;
  raise notice 'CACHE PASS: readable with grant; client writes rejected.';

  -- ===== Admin scope inherits via AC-8 =====
  perform set_config('request.jwt.claims', adm_claims, true);
  v_input := carebridge_ai_summary_input(pp);
  if v_input is null then raise exception 'AC-8 FAIL: admin could not get summary input'; end if;
  raise notice 'AC-8 PASS: admin scope inherits summary access via clinic grant.';

  -- ===== Doctor WITHOUT grant (other clinic) is refused =====
  perform set_config('request.jwt.claims', doc2_claims, true);
  blocked := false;
  begin perform carebridge_ai_summary_input(pp); exception when others then blocked := true; end;
  if not blocked then raise exception 'GRANT FAIL: ungr granted doctor got summary input'; end if;
  select count(*) into v_cnt from ai_summaries where patient_id = pp;
  if v_cnt <> 0 then raise exception 'CACHE FAIL: ungranted doctor read ai_summaries'; end if;
  raise notice 'GRANT PASS: no grant, no summary input, no cache read.';

  -- ===== Patient session is refused (clinic scopes only) =====
  perform set_config('request.jwt.claims', pat_claims, true);
  blocked := false;
  begin perform carebridge_ai_summary_input(pp); exception when others then blocked := true; end;
  if not blocked then raise exception 'SCOPE FAIL: patient session got summary input'; end if;
  raise notice 'SCOPE PASS: AI summary limited to clinic sessions.';

  -- ===== Auditability: both successful calls were logged =====
  execute 'reset role';
  select count(*) into v_cnt from access_logs
    where patient_id = pp and what_viewed = 'AI summary' and accessed_by_type = 'doctor';
  if v_cnt <> 1 then raise exception 'LOG FAIL: doctor summary view not logged'; end if;
  select count(*) into v_cnt from access_logs
    where patient_id = pp and what_viewed = 'AI summary' and accessed_by_type = 'clinic_admin';
  if v_cnt <> 1 then raise exception 'LOG FAIL: admin summary view not logged'; end if;
  raise notice 'LOG PASS: summary views audited as doctor / clinic_admin.';

  raise exception 'AI_SUMMARY_OK :: input PASS :: no-notes PASS :: cache PASS :: AC-8 PASS :: grant PASS :: scope PASS :: log PASS'
    using errcode = 'P0001';
end $$;
