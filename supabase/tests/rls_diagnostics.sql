-- CareBridge — Phase 6 Flow C trust tests (database level). Single DO block:
-- seeds as owner, then switches between doctor / partner / patient scopes via
-- set_config and exercises the order-scoped grant lifecycle (AC-10), asserting:
--   * doctor ordering an assigned test creates the partner grant immediately;
--   * the partner sees ONLY name + the one ordered test (never history);
--   * a different partner cannot claim an assigned order;
--   * an OPEN order grants nothing until a partner claims its code;
--   * uploading a report auto-CLOSES the grant (partner loses access);
--   * partners may only set sample_collected/in_progress, not report_ready;
--   * ordering a test requires a specific doctor identity (AC-9, admin rejected).
-- Ends with a success-marker RAISE that rolls back the seed.

do $$
declare
  ca uuid := 'cafe0000-0000-0000-0000-0000000000d6';
  d1 uuid := 'd1110000-0000-0000-0000-0000000000d6';
  pp uuid := 'eeee0000-0000-0000-0000-0000000000d6';
  uidp uuid := 'a11c0000-0000-0000-0000-0000000000d6';
  l1 uuid := 'b1ab0000-0000-0000-0000-0000000000d6';
  l2 uuid := 'b2ab0000-0000-0000-0000-0000000000d6';
  uidl1 uuid := 'c1ab0000-0000-0000-0000-0000000000d6';
  uidl2 uuid := 'c2ab0000-0000-0000-0000-0000000000d6';
  doc_claims text := json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d1)::text;
  adm_claims text := json_build_object('clinic_id',ca,'active_role','admin','active_doctor_id',null)::text;
  pat_claims text := json_build_object('sub',uidp,'role','authenticated')::text;
  l1_claims  text := json_build_object('sub',uidl1,'role','authenticated')::text;
  l2_claims  text := json_build_object('sub',uidl2,'role','authenticated')::text;
  v_order uuid; v_code text; v_open_order uuid; v_open_code text;
  v_name text; v_cnt int; v_report uuid; blocked boolean;
begin
  -- ---- seed (owner; RLS bypassed) ----
  insert into auth.users (id) values (uidp), (uidl1), (uidl2);
  insert into clinics (id, name, registration_number) values (ca,'Clinic D','REG-D6');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty)
    values (d1, ca,'Dr One','MC-D6-1','NMC','GP');
  insert into patients (id, name, phone, auth_user_id) values (pp,'Diag P','+91900000d601', uidp);
  insert into diagnostic_partners (id, name, type, registration_number, auth_user_id) values
    (l1,'Lab One','lab','LAB-D6-1', uidl1),
    (l2,'Lab Two','imaging','LAB-D6-2', uidl2);
  -- d1 already holds a standing grant for pp (so the doctor may order tests).
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
    values (pp, 'doctor', d1, 'standing', 'active');

  execute 'set local role authenticated';

  -- ===== Doctor orders an ASSIGNED test to Lab One =====
  perform set_config('request.jwt.claims', doc_claims, true);
  select id, order_code into v_order, v_code
    from carebridge_order_test(pp, 'pathology', 'CBC', l1);
  if v_order is null then raise exception 'ORDER FAIL: assigned order not created'; end if;

  -- The order-scoped grant exists for Lab One straight away (Flow C step 1).
  perform set_config('request.jwt.claims', l1_claims, true);
  if not current_partner_holds_order(v_order) then
    raise exception 'ORDER FAIL: assigned partner has no grant after order';
  end if;

  -- ===== Lab One claims the code -> sees ONLY the narrow fields =====
  select patient_name into v_name from carebridge_claim_order(v_code);
  if v_name <> 'Diag P' then raise exception 'CLAIM FAIL: wrong/absent patient name (%)', v_name; end if;

  -- Privacy-critical: the partner cannot read the patient row or any history.
  select count(*) into v_cnt from patients where id = pp;
  if v_cnt <> 0 then raise exception 'PRIVACY FAIL: partner can read patients row'; end if;
  select count(*) into v_cnt from test_orders;   -- partner has NO direct select policy
  if v_cnt <> 0 then raise exception 'PRIVACY FAIL: partner can read test_orders directly'; end if;
  raise notice 'CLAIM PASS: partner sees name + ordered test only; no patients/test_orders direct read.';

  -- ===== A different partner cannot claim an assigned order =====
  perform set_config('request.jwt.claims', l2_claims, true);
  blocked := false;
  begin perform carebridge_claim_order(v_code); exception when others then blocked := true; end;
  if not blocked then raise exception 'ISOLATION FAIL: Lab Two claimed Lab One''s assigned order'; end if;
  if current_partner_holds_order(v_order) then raise exception 'ISOLATION FAIL: Lab Two holds the order'; end if;
  raise notice 'ISOLATION PASS: a different partner cannot claim an assigned order.';

  -- ===== Partner status updates: progress allowed, report_ready rejected =====
  perform set_config('request.jwt.claims', l1_claims, true);
  perform carebridge_update_order_status(v_order, 'in_progress');
  blocked := false;
  begin perform carebridge_update_order_status(v_order, 'report_ready'); exception when others then blocked := true; end;
  if not blocked then raise exception 'STATUS FAIL: partner set report_ready directly'; end if;

  -- ===== Upload report -> grant auto-closes =====
  v_report := carebridge_upload_report(v_order, 'structured', null, '{"hb": 13.5}'::jsonb);
  if v_report is null then raise exception 'UPLOAD FAIL: no report id returned'; end if;
  if current_partner_holds_order(v_order) then
    raise exception 'UPLOAD FAIL: grant still active after report upload';
  end if;
  -- A second upload now fails (access ended).
  blocked := false;
  begin perform carebridge_upload_report(v_order, 'structured', null, '{}'::jsonb); exception when others then blocked := true; end;
  if not blocked then raise exception 'UPLOAD FAIL: partner uploaded after grant closed'; end if;
  raise notice 'UPLOAD PASS: report closes the order-scoped grant; further access denied.';

  -- Patient can see their own order + report (RLS), report_ready status set.
  perform set_config('request.jwt.claims', pat_claims, true);
  select count(*) into v_cnt from test_orders where patient_id = pp and status = 'report_ready';
  if v_cnt < 1 then raise exception 'PATIENT FAIL: patient cannot see report_ready order'; end if;
  select count(*) into v_cnt from test_reports r join test_orders o on o.id = r.test_order_id where o.patient_id = pp;
  if v_cnt < 1 then raise exception 'PATIENT FAIL: patient cannot see their report'; end if;
  raise notice 'PATIENT PASS: patient sees own order + uploaded report.';

  -- ===== OPEN order: no grant until a partner claims it =====
  perform set_config('request.jwt.claims', doc_claims, true);
  select id, order_code into v_open_order, v_open_code
    from carebridge_order_test(pp, 'imaging', 'Chest X-Ray', null);  -- open (no partner)
  perform set_config('request.jwt.claims', l1_claims, true);
  if current_partner_holds_order(v_open_order) then
    raise exception 'OPEN FAIL: open order granted access before claim';
  end if;
  perform carebridge_claim_order(v_open_code);
  if not current_partner_holds_order(v_open_order) then
    raise exception 'OPEN FAIL: claiming open order did not create grant';
  end if;
  raise notice 'OPEN PASS: open order grants nothing until a partner claims the code.';

  -- ===== AC-9: admin scope may NOT order a test =====
  perform set_config('request.jwt.claims', adm_claims, true);
  blocked := false;
  begin perform carebridge_order_test(pp, 'pathology', 'LFT', l1); exception when others then blocked := true; end;
  if not blocked then raise exception 'AC-9 FAIL: admin scope ordered a test'; end if;
  raise notice 'AC-9 PASS: ordering a test requires a specific doctor identity.';

  raise exception 'DIAGNOSTICS_OK :: order+grant PASS :: claim narrow PASS :: isolation PASS :: upload-closes-grant PASS :: open-order PASS :: AC-9 PASS'
    using errcode = 'P0001';
end $$;
