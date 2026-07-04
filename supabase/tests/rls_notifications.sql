-- CareBridge — Phase 8 notification trust tests (database level). Single DO
-- block; seeds as owner, switches scopes via set_config, asserting:
--   * booking an appointment enqueues a reminder 24h before (trigger);
--   * a visit with a follow-up date enqueues a follow-up reminder (trigger);
--   * uploading a report enqueues a report_ready notification immediately;
--   * a patient sees ONLY their own notifications (RLS);
--   * a client session cannot INSERT notifications (server-write-only);
--   * device_tokens: a user manages only their own token rows.
-- Ends with a success-marker RAISE that rolls back the seed.

do $$
declare
  ca uuid := 'cafe0000-0000-0000-0000-0000000000d8';
  d1 uuid := 'd1110000-0000-0000-0000-0000000000d8';
  p1 uuid := 'e1110000-0000-0000-0000-0000000000d8';
  p2 uuid := 'e2220000-0000-0000-0000-0000000000d8';
  uid1 uuid := 'a1110000-0000-0000-0000-0000000000d8';
  uid2 uuid := 'a2220000-0000-0000-0000-0000000000d8';
  l1 uuid := 'b1ab0000-0000-0000-0000-0000000000d8';
  uidl uuid := 'c1ab0000-0000-0000-0000-0000000000d8';
  doc_claims text := json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d1)::text;
  pat1_claims text := json_build_object('sub',uid1,'role','authenticated')::text;
  pat2_claims text := json_build_object('sub',uid2,'role','authenticated')::text;
  lab_claims  text := json_build_object('sub',uidl,'role','authenticated')::text;
  v_order uuid; v_code text; v_cnt int; blocked boolean;
begin
  -- ---- seed (owner; RLS bypassed) ----
  insert into auth.users (id) values (uid1), (uid2), (uidl);
  insert into clinics (id, name, registration_number) values (ca,'Clinic N','REG-D8');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty)
    values (d1, ca,'Dr N','MC-D8-1','NMC','GP');
  insert into patients (id, name, phone, auth_user_id) values
    (p1,'Notif P1','+91900000d801', uid1),
    (p2,'Notif P2','+91900000d802', uid2);
  insert into diagnostic_partners (id, name, type, registration_number, auth_user_id)
    values (l1,'Lab N','lab','LAB-D8-1', uidl);
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
    values (p1, 'doctor', d1, 'standing', 'active');

  -- ===== Trigger: appointment booking enqueues a 24h-before reminder =====
  insert into appointments (patient_id, doctor_id, clinic_id, scheduled_time)
    values (p1, d1, ca, now() + interval '3 days');
  select count(*) into v_cnt from notifications
    where patient_id = p1 and type = 'appointment_reminder'
      and scheduled_for between now() + interval '47 hours' and now() + interval '49 hours';
  if v_cnt <> 1 then raise exception 'APPT FAIL: reminder not enqueued 24h before'; end if;

  -- A same-day appointment (less than 24h away) enqueues nothing.
  insert into appointments (patient_id, doctor_id, clinic_id, scheduled_time)
    values (p1, d1, ca, now() + interval '2 hours');
  select count(*) into v_cnt from notifications where patient_id = p1 and type = 'appointment_reminder';
  if v_cnt <> 1 then raise exception 'APPT FAIL: same-day booking should not enqueue'; end if;
  raise notice 'APPT PASS: 24h reminder enqueued; same-day booking skipped.';

  -- ===== Trigger: follow-up date on a visit enqueues a reminder =====
  insert into visits (patient_id, doctor_id, clinic_id, diagnosis, follow_up_date)
    values (p1, d1, ca, 'check', (now() + interval '10 days')::date);
  select count(*) into v_cnt from notifications where patient_id = p1 and type = 'follow_up';
  if v_cnt <> 1 then raise exception 'FOLLOWUP FAIL: reminder not enqueued'; end if;
  raise notice 'FOLLOWUP PASS: follow-up reminder enqueued for the follow-up date.';

  -- ===== Report upload enqueues report_ready immediately =====
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', doc_claims, true);
  select id, order_code into v_order, v_code from carebridge_order_test(p1, 'pathology', 'CBC', l1);
  perform set_config('request.jwt.claims', lab_claims, true);
  perform carebridge_claim_order(v_code);
  perform carebridge_upload_report(v_order, 'structured', null, '{"hb": 12.1}'::jsonb);

  execute 'reset role';
  select count(*) into v_cnt from notifications
    where patient_id = p1 and type = 'report_ready' and scheduled_for <= now();
  if v_cnt <> 1 then raise exception 'REPORT FAIL: report_ready not enqueued on upload'; end if;
  raise notice 'REPORT PASS: report_ready notification enqueued at upload time.';

  -- ===== RLS: p1 sees own feed; p2 sees NOTHING of p1''s =====
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', pat1_claims, true);
  select count(*) into v_cnt from notifications;
  if v_cnt <> 3 then raise exception 'RLS FAIL: p1 should see exactly 3 own notifications, saw %', v_cnt; end if;
  perform set_config('request.jwt.claims', pat2_claims, true);
  select count(*) into v_cnt from notifications;
  if v_cnt <> 0 then raise exception 'RLS FAIL: p2 sees another patient''s notifications'; end if;
  raise notice 'RLS PASS: notification feed is patient-private.';

  -- ===== Clients cannot write the queue =====
  perform set_config('request.jwt.claims', pat1_claims, true);
  blocked := false;
  begin
    insert into notifications (patient_id, type, scheduled_for) values (p1, 'forged', now());
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'WRITE FAIL: client inserted a notification'; end if;
  raise notice 'WRITE PASS: notification queue is server-write-only.';

  -- ===== device_tokens: own rows only =====
  insert into device_tokens (auth_user_id, fcm_token, platform) values (uid1, 'tok-d8-p1', 'ios');
  perform set_config('request.jwt.claims', pat2_claims, true);
  select count(*) into v_cnt from device_tokens;
  if v_cnt <> 0 then raise exception 'TOKEN FAIL: p2 can see p1 device token'; end if;
  blocked := false;
  begin
    insert into device_tokens (auth_user_id, fcm_token) values (uid1, 'tok-forged');
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'TOKEN FAIL: p2 registered a token for p1'; end if;
  perform set_config('request.jwt.claims', pat1_claims, true);
  insert into device_tokens (auth_user_id, fcm_token, platform) values (uid1, 'tok-d8-p1b', 'web');
  select count(*) into v_cnt from device_tokens;
  if v_cnt <> 2 then raise exception 'TOKEN FAIL: p1 cannot manage own tokens'; end if;
  raise notice 'TOKEN PASS: device tokens are per-user private.';

  raise exception 'NOTIFICATIONS_OK :: appt PASS :: follow-up PASS :: report-ready PASS :: RLS PASS :: server-write-only PASS :: tokens PASS'
    using errcode = 'P0001';
end $$;
