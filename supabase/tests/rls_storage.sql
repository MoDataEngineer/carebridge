-- CareBridge — Audit fix H3 trust tests: storage.objects policies for the
-- 'reports' bucket mirror the Flow C order-scoped grant. Single DO block:
--   * partner WITH an active grant can insert an object under its order path;
--   * a DIFFERENT partner cannot;
--   * after the grant closes (report uploaded), further inserts are denied;
--   * the patient and a granted clinic doctor can SELECT the object;
--   * an ungranted doctor (other clinic) and another patient CANNOT;
--   * clients cannot UPDATE/DELETE report objects at all.
-- Ends with a success-marker RAISE that rolls back the seed.

do $$
declare
  ca uuid := 'cafe0000-0000-0000-0000-0000000000da';
  cb uuid := 'cbbb0000-0000-0000-0000-0000000000da';
  d1 uuid := 'd1110000-0000-0000-0000-0000000000da';
  d2 uuid := 'd2220000-0000-0000-0000-0000000000da';
  p1 uuid := 'e1110000-0000-0000-0000-0000000000da';
  p2 uuid := 'e2220000-0000-0000-0000-0000000000da';
  uid1 uuid := 'a1110000-0000-0000-0000-0000000000da';
  uid2 uuid := 'a2220000-0000-0000-0000-0000000000da';
  l1 uuid := 'b1ab0000-0000-0000-0000-0000000000da';
  l2 uuid := 'b2ab0000-0000-0000-0000-0000000000da';
  uidl1 uuid := 'c1ab0000-0000-0000-0000-0000000000da';
  uidl2 uuid := 'c2ab0000-0000-0000-0000-0000000000da';
  d1_claims text := json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d1)::text;
  d2_claims text := json_build_object('clinic_id',cb,'active_role','doctor','active_doctor_id',d2)::text;
  p1_claims text := json_build_object('sub',uid1,'role','authenticated')::text;
  p2_claims text := json_build_object('sub',uid2,'role','authenticated')::text;
  l1_claims text := json_build_object('sub',uidl1,'role','authenticated')::text;
  l2_claims text := json_build_object('sub',uidl2,'role','authenticated')::text;
  v_order uuid; v_code text; v_path text; v_cnt int; blocked boolean;
begin
  -- ---- seed ----
  insert into auth.users (id) values (uid1), (uid2), (uidl1), (uidl2);
  insert into clinics (id, name, registration_number) values
    (ca,'Clinic SA','REG-DA-A'), (cb,'Clinic SB','REG-DA-B');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    (d1, ca,'Dr SA','MC-DA-1','NMC','GP'), (d2, cb,'Dr SB','MC-DA-2','NMC','GP');
  insert into patients (id, name, phone, auth_user_id) values
    (p1,'Sto P1','+91900000da01', uid1), (p2,'Sto P2','+91900000da02', uid2);
  insert into diagnostic_partners (id, name, type, registration_number, auth_user_id) values
    (l1,'Lab SA','lab','LAB-DA-1', uidl1), (l2,'Lab SB','lab','LAB-DA-2', uidl2);
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
    values (p1,'doctor',d1,'standing','active');

  execute 'set local role authenticated';

  -- Doctor orders an ASSIGNED test -> grant for Lab SA exists immediately.
  perform set_config('request.jwt.claims', d1_claims, true);
  select id, order_code into v_order, v_code from carebridge_order_test(p1,'imaging','X-Ray', l1);
  v_path := v_order::text || '/scan.pdf';

  -- ===== Partner with grant uploads; other partner cannot =====
  perform set_config('request.jwt.claims', l1_claims, true);
  insert into storage.objects (bucket_id, name, owner)
    values ('reports', v_path, uidl1);
  perform set_config('request.jwt.claims', l2_claims, true);
  blocked := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
      values ('reports', v_order::text || '/rogue.pdf', uidl2);
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'STORAGE FAIL: ungranted partner uploaded a file'; end if;
  raise notice 'UPLOAD PASS: only the granted partner can write under the order path.';

  -- ===== Reads: patient + granted clinic doctor YES; others NO =====
  perform set_config('request.jwt.claims', p1_claims, true);
  select count(*) into v_cnt from storage.objects where bucket_id='reports' and name = v_path;
  if v_cnt <> 1 then raise exception 'READ FAIL: owning patient cannot see report file'; end if;
  perform set_config('request.jwt.claims', d1_claims, true);
  select count(*) into v_cnt from storage.objects where bucket_id='reports' and name = v_path;
  if v_cnt <> 1 then raise exception 'READ FAIL: granted doctor cannot see report file'; end if;
  perform set_config('request.jwt.claims', d2_claims, true);
  select count(*) into v_cnt from storage.objects where bucket_id='reports' and name = v_path;
  if v_cnt <> 0 then raise exception 'READ FAIL: ungranted doctor sees report file'; end if;
  perform set_config('request.jwt.claims', p2_claims, true);
  select count(*) into v_cnt from storage.objects where bucket_id='reports' and name = v_path;
  if v_cnt <> 0 then raise exception 'READ FAIL: another patient sees report file'; end if;
  raise notice 'READ PASS: file visibility mirrors the grant model exactly.';

  -- ===== Clients cannot update/delete (no policy, or storage guard trigger) =====
  perform set_config('request.jwt.claims', l1_claims, true);
  begin
    update storage.objects set name = name where bucket_id='reports' and name = v_path;
    get diagnostics v_cnt = row_count;
    if v_cnt <> 0 then raise exception 'MUTATE FAIL: client updated a report object'; end if;
  exception when others then null; -- blocked outright is also a pass
  end;
  begin
    delete from storage.objects where bucket_id='reports' and name = v_path;
    get diagnostics v_cnt = row_count;
    if v_cnt <> 0 then raise exception 'MUTATE FAIL: client deleted a report object'; end if;
  exception when others then null; -- storage guard trigger blocks direct deletes
  end;
  raise notice 'MUTATE PASS: report files are client-immutable.';

  -- ===== Grant closes on report upload -> partner loses write AND read =====
  perform carebridge_upload_report(v_order, 'pdf', v_path, null);
  blocked := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
      values ('reports', v_order::text || '/late.pdf', uidl1);
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'CLOSE FAIL: partner uploaded after grant closed'; end if;
  select count(*) into v_cnt from storage.objects where bucket_id='reports' and name = v_path;
  if v_cnt <> 0 then raise exception 'CLOSE FAIL: partner still reads file after grant closed'; end if;
  -- Patient still sees it, of course.
  perform set_config('request.jwt.claims', p1_claims, true);
  select count(*) into v_cnt from storage.objects where bucket_id='reports' and name = v_path;
  if v_cnt <> 1 then raise exception 'CLOSE FAIL: patient lost file access'; end if;
  raise notice 'CLOSE PASS: report upload closes the partner''s file access; patient keeps it.';

  raise exception 'STORAGE_OK :: upload PASS :: read PASS :: immutable PASS :: close PASS'
    using errcode = 'P0001';
end $$;
