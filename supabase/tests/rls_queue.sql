-- CareBridge — Phase 10 trust tests (live queue). Single DO block asserting:
--   * appointments visibility: doctor scope sees ONLY own rows; admin scope
--     sees clinic-wide, never another clinic's (guarantees b/c on scheduling).
--   * carebridge_live_queue(): doctor gets own queue, admin gets clinic-wide,
--     rows carry the patient name (narrow columns).
--   * check-in: tokens are sequential per doctor per day; admin may check in;
--     a doctor cannot check in another doctor's appointment; FREE clinic is
--     refused (Section 9 paid gate).
--   * call-next: promotes lowest waiting token, completes the previous one;
--     admin scope refused (the room is the doctor's call).
-- Ends with a success-marker RAISE that rolls back the seed.

do $$
declare
  cp uuid := 'caa00000-0000-0000-0000-000000000d10';  -- PAID clinic
  cf uuid := 'cbb00000-0000-0000-0000-000000000d10';  -- FREE clinic
  d1 uuid := 'd1100000-0000-0000-0000-000000000d10';  -- paid clinic doc 1
  d2 uuid := 'd2200000-0000-0000-0000-000000000d10';  -- paid clinic doc 2
  d3 uuid := 'd3300000-0000-0000-0000-000000000d10';  -- free clinic doc
  p1 uuid := 'e1100000-0000-0000-0000-000000000d10';
  p2 uuid := 'e2200000-0000-0000-0000-000000000d10';
  p3 uuid := 'e3300000-0000-0000-0000-000000000d10';
  a1 uuid; a2 uuid; a3 uuid; a4 uuid;
  v_cnt int; v_tok int; v_next uuid; blocked boolean;
  d1_claims text := json_build_object('clinic_id',cp,'active_role','doctor','active_doctor_id',d1)::text;
  d2_claims text := json_build_object('clinic_id',cp,'active_role','doctor','active_doctor_id',d2)::text;
  d3_claims text := json_build_object('clinic_id',cf,'active_role','doctor','active_doctor_id',d3)::text;
  adm_claims text := json_build_object('clinic_id',cp,'active_role','admin','active_doctor_id',null)::text;
begin
  -- ---- seed: today's appointments (a1,a2 -> d1; a3 -> d2; a4 -> free d3) ----
  insert into clinics (id, name, registration_number, subscription_status) values
    (cp,'Paid Clinic Q','REG-Q-P','paid'), (cf,'Free Clinic Q','REG-Q-F','free');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    (d1, cp,'Dr Q One','MC-Q-1','NMC','GP'),
    (d2, cp,'Dr Q Two','MC-Q-2','NMC','GP'),
    (d3, cf,'Dr Q Three','MC-Q-3','NMC','GP');
  insert into patients (id, name, phone) values
    (p1,'Queue Pat 1','+91900000q101'),
    (p2,'Queue Pat 2','+91900000q102'),
    (p3,'Queue Pat 3','+91900000q103');
  insert into appointments (id, patient_id, doctor_id, clinic_id, scheduled_time)
    values (gen_random_uuid(), p1, d1, cp, now() + interval '1 hour') returning id into a1;
  insert into appointments (id, patient_id, doctor_id, clinic_id, scheduled_time)
    values (gen_random_uuid(), p2, d1, cp, now() + interval '2 hours') returning id into a2;
  insert into appointments (id, patient_id, doctor_id, clinic_id, scheduled_time)
    values (gen_random_uuid(), p3, d2, cp, now() + interval '1 hour') returning id into a3;
  insert into appointments (id, patient_id, doctor_id, clinic_id, scheduled_time)
    values (gen_random_uuid(), p3, d3, cf, now() + interval '1 hour') returning id into a4;

  execute 'set local role authenticated';

  -- ===== Visibility: doctor own rows only; admin clinic-wide only =====
  perform set_config('request.jwt.claims', d1_claims, true);
  select count(*) into v_cnt from appointments where id in (a1,a2,a3,a4);
  if v_cnt <> 2 then raise exception 'SEE FAIL: doctor scope sees % rows, expected own 2', v_cnt; end if;
  perform set_config('request.jwt.claims', adm_claims, true);
  select count(*) into v_cnt from appointments where id in (a1,a2,a3,a4);
  if v_cnt <> 3 then raise exception 'SEE FAIL: admin sees % rows, expected clinic-wide 3', v_cnt; end if;
  raise notice 'SEE PASS: doctor sees own appointments; admin sees clinic-wide, not other clinics.';

  -- ===== Queue reader: scope-aware, carries names =====
  perform set_config('request.jwt.claims', d1_claims, true);
  select count(*) into v_cnt from carebridge_live_queue();
  if v_cnt <> 2 then raise exception 'QUEUE FAIL: doctor queue has % rows, expected 2', v_cnt; end if;
  select count(*) into v_cnt from carebridge_live_queue() q where q.patient_name = 'Queue Pat 1';
  if v_cnt <> 1 then raise exception 'QUEUE FAIL: queue row missing patient name'; end if;
  perform set_config('request.jwt.claims', adm_claims, true);
  select count(*) into v_cnt from carebridge_live_queue();
  if v_cnt <> 3 then raise exception 'QUEUE FAIL: admin queue has % rows, expected 3', v_cnt; end if;
  raise notice 'QUEUE PASS: live queue is doctor-own vs admin clinic-wide, name-only rows.';

  -- ===== Check-in: sequential tokens; admin allowed; cross-doctor blocked =====
  perform set_config('request.jwt.claims', d1_claims, true);
  v_tok := carebridge_checkin_appointment(a1);
  if v_tok <> 1 then raise exception 'TOKEN FAIL: first token was %, expected 1', v_tok; end if;
  perform set_config('request.jwt.claims', adm_claims, true);  -- front desk
  v_tok := carebridge_checkin_appointment(a2);
  if v_tok <> 2 then raise exception 'TOKEN FAIL: second token was %, expected 2', v_tok; end if;
  -- d2 has their own counter.
  perform set_config('request.jwt.claims', d2_claims, true);
  v_tok := carebridge_checkin_appointment(a3);
  if v_tok <> 1 then raise exception 'TOKEN FAIL: tokens not per-doctor (d2 got %)', v_tok; end if;
  -- d2 cannot touch d1's queue.
  blocked := false;
  begin perform carebridge_checkin_appointment(a1); exception when others then blocked := true; end;
  if not blocked then raise exception 'TOKEN FAIL: doctor checked in another doctor''s appointment'; end if;
  raise notice 'TOKEN PASS: per-doctor sequential tokens; admin may check in; cross-doctor blocked.';

  -- ===== Paid gate (Section 9): free clinic refused =====
  perform set_config('request.jwt.claims', d3_claims, true);
  blocked := false;
  begin perform carebridge_checkin_appointment(a4); exception when others then blocked := true; end;
  if not blocked then raise exception 'GATE FAIL: free clinic used the token tracker'; end if;
  blocked := false;
  begin perform carebridge_call_next(); exception when others then blocked := true; end;
  if not blocked then raise exception 'GATE FAIL: free clinic called next'; end if;
  raise notice 'GATE PASS: token flow refused on the free tier.';

  -- ===== Call-next: lowest token first, previous completed; admin refused =====
  perform set_config('request.jwt.claims', adm_claims, true);
  blocked := false;
  begin perform carebridge_call_next(); exception when others then blocked := true; end;
  if not blocked then raise exception 'NEXT FAIL: admin scope called next (doctor-only)'; end if;
  perform set_config('request.jwt.claims', d1_claims, true);
  v_next := carebridge_call_next();
  if v_next <> a1 then raise exception 'NEXT FAIL: called %, expected token 1 (a1)', v_next; end if;
  v_next := carebridge_call_next();
  if v_next <> a2 then raise exception 'NEXT FAIL: called %, expected token 2 (a2)', v_next; end if;
  select count(*) into v_cnt from appointments where id = a1 and status = 'completed';
  if v_cnt <> 1 then raise exception 'NEXT FAIL: previous consultation not completed'; end if;
  v_next := carebridge_call_next();  -- queue empty now
  if v_next is not null then raise exception 'NEXT FAIL: called someone from an empty queue'; end if;
  raise notice 'NEXT PASS: lowest token called, previous completed, empty queue returns null.';

  raise exception 'QUEUE_OK :: see PASS :: queue PASS :: tokens PASS :: gate PASS :: next PASS'
    using errcode = 'P0001';
end $$;
