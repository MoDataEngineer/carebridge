-- CareBridge — Phase 5 consent-flow trust tests (database level). Single DO block:
-- seeds as owner, then switches between patient / doctor / admin scopes via
-- set_config and exercises the Flow A, Flow B, revoke and AC-8 paths, asserting
-- current_scope_can_view_patient() flips exactly as consent changes. Ends with a
-- success-marker RAISE that rolls back the seed.
--
-- Clinic A: doctors D1, D2. Patient P (auth user uidP). Starts with NO grants.

do $$
declare
  ca uuid := 'cafe0000-0000-0000-0000-0000000000c5';
  d1 uuid := 'd1110000-0000-0000-0000-0000000000c5';
  d2 uuid := 'd2220000-0000-0000-0000-0000000000c5';
  pp uuid := 'eeee0000-0000-0000-0000-0000000000c5';
  uidp uuid := 'a11c0000-0000-0000-0000-0000000000c5';
  doc_claims  text := json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d1)::text;
  doc2_claims text := json_build_object('clinic_id',ca,'active_role','doctor','active_doctor_id',d2)::text;
  adm_claims  text := json_build_object('clinic_id',ca,'active_role','admin','active_doctor_id',null)::text;
  pat_claims  text := json_build_object('sub',uidp,'role','authenticated')::text;
  v_code text; v_grant uuid; v_logs int; v_status text; blocked boolean;
begin
  -- ---- seed (owner; RLS bypassed) ----
  insert into auth.users (id) values (uidp);
  insert into clinics (id, name, registration_number) values (ca,'Clinic C','REG-C5');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    (d1, ca,'Dr One','MC-C5-1','NMC','GP'),
    (d2, ca,'Dr Two','MC-C5-2','NMC','Derm');
  insert into patients (id, name, phone, auth_user_id) values (pp,'Consent P','+91900000c501', uidp);
  -- Pre-seed an already-expired code (owner insert; clients have no INSERT policy).
  insert into consent_codes (patient_id, code, expires_at)
    values (pp, 'expiredcode_c5', now() - interval '1 minute');

  execute 'set local role authenticated';

  -- ===== baseline: no grant -> D1 cannot see P =====
  perform set_config('request.jwt.claims', doc_claims, true);
  if current_scope_can_view_patient(pp) then raise exception 'PRE FAIL: D1 sees P with no grant'; end if;

  -- ===== Flow A: patient mints a code, D1 redeems it =====
  perform set_config('request.jwt.claims', pat_claims, true);
  select c.code into v_code from carebridge_create_consent_code() c;
  if v_code is null then raise exception 'FLOW A FAIL: no consent code minted'; end if;

  perform set_config('request.jwt.claims', doc_claims, true);
  perform carebridge_redeem_consent_code(v_code);
  if not current_scope_can_view_patient(pp) then raise exception 'FLOW A FAIL: D1 cannot see P after redeem'; end if;

  -- D2 (other doctor) must NOT see P from D1's grant (isolation).
  perform set_config('request.jwt.claims', doc2_claims, true);
  if current_scope_can_view_patient(pp) then raise exception 'FLOW A FAIL: D2 sees P from D1 grant'; end if;

  -- AC-8: admin of clinic A inherits visibility via D1's grant.
  perform set_config('request.jwt.claims', adm_claims, true);
  if not current_scope_can_view_patient(pp) then raise exception 'AC-8 FAIL: admin does not inherit P'; end if;
  raise notice 'FLOW A + AC-8 PASS: D1 redeem grants access; D2 isolated; admin inherits.';

  -- access log written for the consent event (patient can read own log).
  perform set_config('request.jwt.claims', pat_claims, true);
  select count(*) into v_logs from access_logs where patient_id = pp;
  if v_logs < 1 then raise exception 'LOG FAIL: no access_log row for consent'; end if;

  -- ===== Revoke: patient revokes -> D1 loses visibility =====
  select id into v_grant from access_grants
    where patient_id = pp and granted_to_id = d1 and status = 'active';
  perform carebridge_revoke_grant(v_grant);
  perform set_config('request.jwt.claims', doc_claims, true);
  if current_scope_can_view_patient(pp) then raise exception 'REVOKE FAIL: D1 still sees P after revoke'; end if;
  raise notice 'REVOKE PASS: patient revoke removes D1 visibility.';

  -- ===== Flow B: doctor requests, pending != visible, patient approves =====
  perform set_config('request.jwt.claims', doc_claims, true);
  v_grant := carebridge_request_access(pp);
  if current_scope_can_view_patient(pp) then raise exception 'FLOW B FAIL: pending request grants premature access'; end if;

  perform set_config('request.jwt.claims', pat_claims, true);
  v_status := carebridge_respond_access(v_grant, true);
  if v_status <> 'active' then raise exception 'FLOW B FAIL: approve did not activate (got %)', v_status; end if;

  perform set_config('request.jwt.claims', doc_claims, true);
  if not current_scope_can_view_patient(pp) then raise exception 'FLOW B FAIL: D1 cannot see P after approval'; end if;
  raise notice 'FLOW B PASS: request is pending (no access) until patient approves.';

  -- ===== Negatives: expired code rejected; respond on non-pending rejected =====
  perform set_config('request.jwt.claims', doc_claims, true);   -- doctor tries the expired code
  blocked := false;
  begin
    perform carebridge_redeem_consent_code('expiredcode_c5');
  exception when others then blocked := true; end;
  if not blocked then raise exception 'NEG FAIL: expired consent code was accepted'; end if;

  perform set_config('request.jwt.claims', pat_claims, true);
  blocked := false;
  begin
    perform carebridge_respond_access(v_grant, true);  -- already active, not pending
  exception when others then blocked := true; end;
  if not blocked then raise exception 'NEG FAIL: responding to a non-pending grant was accepted'; end if;
  raise notice 'NEGATIVE PASS: expired code + non-pending response both rejected.';

  raise exception 'CONSENT_OK :: Flow A PASS :: AC-8 inherit PASS :: revoke PASS :: Flow B approve PASS :: negatives PASS'
    using errcode = 'P0001';
end $$;
