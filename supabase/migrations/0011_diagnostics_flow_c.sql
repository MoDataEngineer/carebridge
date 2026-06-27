-- CareBridge — Phase 6: diagnostic-partner integration (Section 5.3, Flow C).
-- The order-scoped grant is the privacy-critical piece: a partner may see ONLY
-- the patient's name, the one ordered test, and the ordering doctor/clinic —
-- NEVER visit history or anything else. Enforced at the DATABASE level.
--
-- Identity model (Section 2.3): a diagnostic partner is FLAT — one GoTrue user
-- per lab, no nested staff, no scope picker. So we mirror the PATIENT pattern
-- (migration 0005), not the clinic scope pattern: diagnostic_partners.auth_user_id
-- links the GoTrue user, and current_partner_id() resolves it from auth.uid().
-- No custom-access-token-hook change is needed.
--
-- Flow C lifecycle (Section 7):
--   * doctor orders a test -> test_orders row created;
--       - if a specific partner is named -> order_scoped grant created NOW;
--       - if left open -> grant created only when a partner CLAIMS the code.
--   * grant closes automatically the moment a report is uploaded, or after a
--     30-day expiry — whichever is first.
--
-- Partner data access is FUNCTION-ONLY: every partner read goes through a
-- SECURITY DEFINER function that returns explicit narrow columns. Partners get
-- no raw SELECT on patients/visits, so the "name + ordered test only" rule
-- cannot be bypassed by a crafted PostgREST query.

-- ============================================================
-- Partner identity — link a partner to its GoTrue auth user.
-- ============================================================
alter table diagnostic_partners
  add column if not exists auth_user_id uuid references auth.users(id);

create unique index if not exists idx_partners_auth_user
  on diagnostic_partners(auth_user_id) where auth_user_id is not null;

-- Resolve the current partner's id from the verified auth.uid().
-- SECURITY DEFINER so the lookup isn't itself filtered by RLS (mirrors
-- current_patient_id() in 0005).
create or replace function public.current_partner_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from diagnostic_partners where auth_user_id = auth.uid()
$$;

-- ============================================================
-- Whether an ACTIVE order-scoped grant ties the current partner to an order.
-- Single source of truth for "can this partner touch this order?". SECURITY
-- DEFINER so the access_grants lookup isn't blocked by RLS.
-- ============================================================
create or replace function public.current_partner_holds_order(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from access_grants g
    where g.test_order_id = p_order
      and g.granted_to_type = 'diagnostic_partner'
      and g.granted_to_id = current_partner_id()
      and g.type = 'order_scoped'
      and g.status = 'active'
      and g.revoked_at is null
      and (g.expires_at is null or g.expires_at > now())
  )
$$;

-- ============================================================
-- test_orders / test_reports — table privileges + RLS for the PATIENT and
-- DOCTOR/ADMIN sides. (The partner side is function-only, below.)
-- ============================================================
grant select on test_orders, test_reports to authenticated;

-- test_orders: visible to the patient who owns it, and to a doctor/admin scope
-- that can already view that patient (reuses the Phase 2/5 visibility helper).
drop policy if exists test_orders_select_patient on test_orders;
create policy test_orders_select_patient on test_orders
  for select to authenticated
  using (patient_id = current_patient_id());

drop policy if exists test_orders_select_clinic on test_orders;
create policy test_orders_select_clinic on test_orders
  for select to authenticated
  using (
    exists (
      select 1 from doctors d
      where d.id = test_orders.doctor_id and d.clinic_id = current_clinic_id()
    )
    and public.current_scope_can_view_patient(patient_id)
  );

-- test_reports: follow the parent order's visibility for patient + clinic.
drop policy if exists test_reports_select_patient on test_reports;
create policy test_reports_select_patient on test_reports
  for select to authenticated
  using (
    exists (
      select 1 from test_orders o
      where o.id = test_order_id and o.patient_id = current_patient_id()
    )
  );

drop policy if exists test_reports_select_clinic on test_reports;
create policy test_reports_select_clinic on test_reports
  for select to authenticated
  using (
    exists (
      select 1 from test_orders o
      join doctors d on d.id = o.doctor_id
      where o.id = test_order_id
        and d.clinic_id = current_clinic_id()
        and public.current_scope_can_view_patient(o.patient_id)
    )
  );

-- ============================================================
-- DOCTOR side — order a test (Flow C step 1).
-- ============================================================
-- Creates the order under the calling doctor's identity. If a specific partner
-- is named, the order-scoped grant is created immediately (step 1); an open
-- order defers the grant until a partner claims the code (step 4).
create or replace function carebridge_order_test(
  p_patient    uuid,
  p_test_type  text,
  p_test_name  text,
  p_partner    uuid default null,
  p_visit      uuid default null
)
returns table (id uuid, order_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor uuid := current_active_doctor_id();
  v_order  test_orders%rowtype;
begin
  -- AC-9: ordering a test is a clinical action — requires a specific doctor.
  if current_active_role() <> 'doctor' or v_doctor is null then
    raise exception 'ordering a test requires a specific doctor identity';
  end if;
  if not public.current_scope_can_view_patient(p_patient) then
    raise exception 'no active grant to order tests for this patient';
  end if;

  insert into test_orders (patient_id, doctor_id, visit_id, diagnostic_partner_id, test_type, test_name)
    values (p_patient, v_doctor, p_visit, p_partner, p_test_type, p_test_name)
    returning * into v_order;

  -- Assigned order -> grant the named partner now (order-scoped, 30-day expiry).
  if p_partner is not null then
    insert into access_grants (patient_id, granted_to_type, granted_to_id, type,
                               test_order_id, status, expires_at)
      values (p_patient, 'diagnostic_partner', p_partner, 'order_scoped',
              v_order.id, 'active', now() + interval '30 days');
  end if;

  return query select v_order.id, v_order.order_code;
end;
$$;

-- ============================================================
-- PARTNER side — claim an order by its code (Flow C step 4 + assigned pickup).
-- ============================================================
-- Returns ONLY the narrow, privacy-safe fields. For an OPEN order, claims it to
-- this partner and creates the order-scoped grant. For an order already assigned
-- to THIS partner, ensures the grant exists. An order assigned to a DIFFERENT
-- partner is rejected.
create or replace function carebridge_claim_order(p_code text)
returns table (
  order_id    uuid,
  patient_name text,
  test_type   text,
  test_name   text,
  doctor_name text,
  clinic_name text,
  status      text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner uuid := current_partner_id();
  v_order   test_orders%rowtype;
begin
  if v_partner is null then
    raise exception 'not a diagnostic-partner session';
  end if;

  select * into v_order from test_orders where order_code = p_code for update;
  if v_order.id is null then
    raise exception 'unknown order code';
  end if;
  if v_order.status = 'cancelled' then
    raise exception 'order was cancelled';
  end if;

  if v_order.diagnostic_partner_id is null then
    -- Open order: claim it and create the order-scoped grant.
    update test_orders set diagnostic_partner_id = v_partner where id = v_order.id;
    v_order.diagnostic_partner_id := v_partner;
  elsif v_order.diagnostic_partner_id <> v_partner then
    raise exception 'order is assigned to a different partner';
  end if;

  -- Ensure an active order-scoped grant exists for this partner.
  if not exists (
    select 1 from access_grants ag
    where ag.test_order_id = v_order.id and ag.granted_to_type = 'diagnostic_partner'
      and ag.granted_to_id = v_partner and ag.status = 'active' and ag.revoked_at is null
  ) then
    insert into access_grants (patient_id, granted_to_type, granted_to_id, type,
                               test_order_id, status, expires_at)
      values (v_order.patient_id, 'diagnostic_partner', v_partner, 'order_scoped',
              v_order.id, 'active', now() + interval '30 days');
  end if;

  -- Log the claim against the patient's audit trail (Section 10).
  insert into access_logs (patient_id, accessed_by_type, accessed_by_id, what_viewed)
    values (v_order.patient_id, 'diagnostic_partner', v_partner,
            'claimed test order: ' || v_order.test_name);

  return query
    select v_order.id, p.name, v_order.test_type, v_order.test_name,
           d.name, c.name, v_order.status::text
    from patients p
    join doctors d on d.id = v_order.doctor_id
    join clinics c on c.id = d.clinic_id
    where p.id = v_order.patient_id;
end;
$$;

-- Partner: list the orders it currently holds an active grant for (its work
-- queue). Narrow columns only — never patient history.
create or replace function carebridge_partner_orders()
returns table (
  order_id    uuid,
  patient_name text,
  test_type   text,
  test_name   text,
  status      text,
  has_report  boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner uuid := current_partner_id();
begin
  if v_partner is null then
    raise exception 'not a diagnostic-partner session';
  end if;
  return query
    select o.id, p.name, o.test_type, o.test_name, o.status::text,
           exists (select 1 from test_reports r where r.test_order_id = o.id)
    from test_orders o
    join patients p on p.id = o.patient_id
    where public.current_partner_holds_order(o.id)
    order by o.created_at desc;
end;
$$;

-- Partner: update an order's progress (sample_collected / in_progress). The
-- terminal report_ready state is set by the upload function, not here.
create or replace function carebridge_update_order_status(p_order uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner uuid := current_partner_id();
begin
  if v_partner is null or not public.current_partner_holds_order(p_order) then
    raise exception 'no active order-scoped grant for this order';
  end if;
  if p_status not in ('sample_collected', 'in_progress') then
    raise exception 'partner may only set sample_collected or in_progress';
  end if;
  update test_orders set status = p_status::test_status where id = p_order;
end;
$$;

-- Partner: upload a result against an order (Flow C step: report). Inserts the
-- report, flips the order to report_ready, and CLOSES the order-scoped grant —
-- the partner loses access the moment the report lands (Section 7 step 3).
create or replace function carebridge_upload_report(
  p_order            uuid,
  p_report_type      text,
  p_file_url         text default null,
  p_structured_values jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner uuid := current_partner_id();
  v_report  uuid;
begin
  if v_partner is null or not public.current_partner_holds_order(p_order) then
    raise exception 'no active order-scoped grant for this order';
  end if;
  if p_report_type not in ('pdf', 'image', 'structured') then
    raise exception 'invalid report type';
  end if;

  insert into test_reports (test_order_id, report_type, file_url, structured_values, uploaded_by)
    values (p_order, p_report_type::report_type, p_file_url, p_structured_values, v_partner)
    returning id into v_report;

  update test_orders set status = 'report_ready' where id = p_order;

  -- Auto-close the grant: access ends the instant the report is uploaded.
  update access_grants
    set status = 'revoked', revoked_at = now()
    where test_order_id = p_order and granted_to_type = 'diagnostic_partner'
      and granted_to_id = v_partner and status = 'active';

  return v_report;
end;
$$;

-- ============================================================
-- Execute grants — clients call these; each authorizes off scope internally.
-- ============================================================
grant execute on function carebridge_order_test(uuid, text, text, uuid, uuid) to authenticated;
grant execute on function carebridge_claim_order(text)                        to authenticated;
grant execute on function carebridge_partner_orders()                         to authenticated;
grant execute on function carebridge_update_order_status(uuid, text)          to authenticated;
grant execute on function carebridge_upload_report(uuid, text, text, jsonb)   to authenticated;
