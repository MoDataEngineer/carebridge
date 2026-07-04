-- CareBridge — Phase 8: notifications (Section 5.1 + build step 8).
--
-- Architecture: the DB is the QUEUE and the audit trail. Enqueue rules run at
-- the database (triggers + the upload-report function), so every insert path
-- enqueues consistently. The notifications Edge Function (cron-invoked)
-- dispatches due rows: FCM push when FCM_SERVICE_ACCOUNT_JSON is configured,
-- and the in-app feed works regardless (patients read their own rows via RLS).
--
-- Notification types enqueued here:
--   appointment_reminder  -> 24h before appointments.scheduled_time (trigger)
--   follow_up             -> 9am on visits.follow_up_date (trigger)
--   report_ready          -> the moment a report is uploaded (function below)
-- Medication reminders are NOT materialized per-dose — the Edge Function
-- computes "due now" from active prescriptions at each slot and enqueues that
-- day's row itself (keeps the table small and the schedule editable).

-- ============================================================
-- device_tokens — FCM registration tokens, one row per device.
-- ============================================================
create table if not exists device_tokens (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid not null references auth.users(id) on delete cascade,
  fcm_token     text not null unique,
  platform      text,                          -- 'ios' | 'android' | 'web'
  created_at    timestamptz not null default now()
);
create index if not exists idx_device_tokens_user on device_tokens(auth_user_id);

alter table device_tokens enable row level security;
grant select, insert, delete on device_tokens to authenticated;

-- A signed-in user manages ONLY their own device tokens.
drop policy if exists device_tokens_own on device_tokens;
create policy device_tokens_own on device_tokens
  for all to authenticated
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- ============================================================
-- notifications — patient reads their own feed; writes are server-side only
-- (triggers/definer functions/service role). No client insert policy.
-- ============================================================
grant select on notifications to authenticated;

drop policy if exists notifications_select_self on notifications;
create policy notifications_select_self on notifications
  for select to authenticated
  using (patient_id = current_patient_id());

-- ============================================================
-- Enqueue: appointment reminder — 24h before, only if that's still in the
-- future at booking time.
-- ============================================================
create or replace function carebridge_enqueue_appointment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.scheduled_time - interval '24 hours' > now() then
    insert into notifications (patient_id, type, payload, scheduled_for)
      values (new.patient_id, 'appointment_reminder',
              jsonb_build_object('appointment_id', new.id,
                                 'scheduled_time', new.scheduled_time),
              new.scheduled_time - interval '24 hours');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_appointment_reminder on appointments;
create trigger trg_appointment_reminder
  after insert on appointments
  for each row execute function carebridge_enqueue_appointment_reminder();

-- ============================================================
-- Enqueue: follow-up reminder — 9am (server time) on the follow-up date.
-- ============================================================
create or replace function carebridge_enqueue_followup_reminder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.follow_up_date is not null
     and (tg_op = 'INSERT' or new.follow_up_date is distinct from old.follow_up_date)
     and (new.follow_up_date::timestamptz + interval '9 hours') > now() then
    insert into notifications (patient_id, type, payload, scheduled_for)
      values (new.patient_id, 'follow_up',
              jsonb_build_object('visit_id', new.id,
                                 'follow_up_date', new.follow_up_date),
              new.follow_up_date::timestamptz + interval '9 hours');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_followup_reminder on visits;
create trigger trg_followup_reminder
  after insert or update of follow_up_date on visits
  for each row execute function carebridge_enqueue_followup_reminder();

-- ============================================================
-- Enqueue: report-ready — recreate carebridge_upload_report (0011) with the
-- notification insert added. Body otherwise unchanged.
-- ============================================================
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
  v_order_row test_orders%rowtype;
begin
  if v_partner is null or not public.current_partner_holds_order(p_order) then
    raise exception 'no active order-scoped grant for this order';
  end if;
  if p_report_type not in ('pdf', 'image', 'structured') then
    raise exception 'invalid report type';
  end if;

  select * into v_order_row from test_orders where id = p_order;

  insert into test_reports (test_order_id, report_type, file_url, structured_values, uploaded_by)
    values (p_order, p_report_type::report_type, p_file_url, p_structured_values, v_partner)
    returning id into v_report;

  update test_orders set status = 'report_ready' where id = p_order;

  -- Auto-close the grant: access ends the instant the report is uploaded.
  update access_grants
    set status = 'revoked', revoked_at = now()
    where test_order_id = p_order and granted_to_type = 'diagnostic_partner'
      and granted_to_id = v_partner and status = 'active';

  -- Phase 8: report-ready notification, due immediately.
  insert into notifications (patient_id, type, payload, scheduled_for)
    values (v_order_row.patient_id, 'report_ready',
            jsonb_build_object('test_order_id', p_order,
                               'test_name', v_order_row.test_name),
            now());

  return v_report;
end;
$$;
