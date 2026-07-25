-- CareBridge — Wearables epic (D14), Phase 12: data model + consent foundation.
--
-- Scope of THIS migration (patient tracker + consent foundation only; the doctor
-- trend view is Phase 13):
--   * three patient-owned tables holding on-device-captured aggregates;
--   * a SEPARATE visibility helper current_scope_can_view_wearables() — a plain
--     clinical grant must never reveal vitals, and clinic admins do NOT
--     auto-inherit (no AC-8 for wearables), per CLAUDE.md §15;
--   * patient self RLS (read/write own) + a doctor read policy gated by the new
--     helper (foundation for P13; no doctor UI reads it yet);
--   * patient-initiated share / revoke RPCs for the 'wearable' grant scope.
--
-- Capture is on-device (HealthKit / Health Connect) and the phone pushes
-- AGGREGATES here; there is no server-side third-party fetch. Data stays in the
-- India-resident project — no cross-border transfer (DPDP, epic §5).

-- ============================================================
-- Tables
-- ============================================================

-- One row per connected source. provider is text (not an enum) so a new hub can
-- be added without a migration.
create table if not exists wearable_connections (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references patients(id) on delete cascade,
  provider      text not null check (provider in ('apple_health', 'health_connect', 'manual')),
  scopes        text[] not null default '{}',      -- OS permission groups granted
  status        text not null default 'active' check (status in ('active', 'revoked')),
  connected_at  timestamptz not null default now(),
  revoked_at    timestamptz,
  unique (patient_id, provider)
);
create index if not exists idx_wearable_conn_patient on wearable_connections(patient_id);

-- The long-term store is DAILY AGGREGATES (keeps continuous streams small).
-- metric_type is free text (steps, active_minutes, calories, resting_hr,
-- sleep_minutes, hrv, spo2, …) so the metric catalogue can grow freely.
create table if not exists wearable_metrics_daily (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references patients(id) on delete cascade,
  metric_type   text not null,
  metric_date   date not null,
  value         numeric,          -- daily total/representative value
  min_value     numeric,
  max_value     numeric,
  avg_value     numeric,
  unit          text,
  source        text,             -- provider the aggregate came from
  updated_at    timestamptz not null default now(),
  unique (patient_id, metric_type, metric_date)
);
create index if not exists idx_wearable_metric_patient_date
  on wearable_metrics_daily(patient_id, metric_date);

-- Per-workout rows. Optional visit_id links a session to a visit's advice for
-- the Phase-13 adherence overlay (mirror test_orders.visit_id: set null on
-- delete so history survives a visit removal).
create table if not exists wearable_workouts (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references patients(id) on delete cascade,
  type          text not null,
  started_at    timestamptz not null,
  duration_min  integer,
  distance_m    numeric,
  avg_hr        integer,
  max_hr        integer,
  calories      integer,
  hr_zones      jsonb,
  visit_id      uuid references visits(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_wearable_workout_patient_start
  on wearable_workouts(patient_id, started_at);

-- ============================================================
-- Visibility helper — DELIBERATELY separate from current_scope_can_view_patient.
-- That helper ignores grant `type`, so a normal clinical 'standing' grant would
-- leak vitals if we reused it. This one requires an active 'wearable' grant to
-- THIS doctor, and has NO admin AC-8 branch (admins never auto-inherit vitals).
-- ============================================================
create or replace function public.current_scope_can_view_wearables(p_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    current_active_role() = 'doctor'
    and current_active_doctor_id() is not null
    and exists (
      select 1
      from access_grants g
      where g.patient_id = p_patient
        and g.granted_to_type = 'doctor'
        and g.granted_to_id = current_active_doctor_id()
        and g.type = 'wearable'
        and g.status = 'active'
        and g.revoked_at is null
        and (g.expires_at is null or g.expires_at > now())
    )
$$;

-- ============================================================
-- Table privileges + RLS
-- ============================================================
grant select, insert, update on
  wearable_connections, wearable_metrics_daily, wearable_workouts
  to authenticated;

alter table wearable_connections   enable row level security;
alter table wearable_metrics_daily enable row level security;
alter table wearable_workouts      enable row level security;

-- Patient reads/writes ONLY their own rows (mirrors 0005 patient self-access).
do $$
declare t text;
begin
  foreach t in array array['wearable_connections','wearable_metrics_daily','wearable_workouts']
  loop
    execute format('drop policy if exists %I_select_self on %I', t, t);
    execute format($p$create policy %I_select_self on %I for select to authenticated
      using (patient_id = public.current_patient_id())$p$, t, t);

    execute format('drop policy if exists %I_insert_self on %I', t, t);
    execute format($p$create policy %I_insert_self on %I for insert to authenticated
      with check (patient_id = public.current_patient_id())$p$, t, t);

    execute format('drop policy if exists %I_update_self on %I', t, t);
    execute format($p$create policy %I_update_self on %I for update to authenticated
      using (patient_id = public.current_patient_id())
      with check (patient_id = public.current_patient_id())$p$, t, t);

    -- Doctor read gated by the WEARABLE helper (foundation for P13). A clinical
    -- grant alone evaluates false here, so vitals never leak through it.
    execute format('drop policy if exists %I_select_doctor on %I', t, t);
    execute format($p$create policy %I_select_doctor on %I for select to authenticated
      using (public.current_scope_can_view_wearables(patient_id))$p$, t, t);
  end loop;
end $$;

-- ============================================================
-- Consent RPCs (patient-initiated only) — the 'wearable' grant scope.
-- No code auto-creates a wearable grant; it exists solely via this RPC, called
-- when the patient turns ON "Share vitals" for a specific doctor.
-- ============================================================
create or replace function carebridge_share_wearables(p_doctor uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := current_patient_id();
  v_grant   uuid;
begin
  if v_patient is null then
    raise exception 'not a patient session';
  end if;

  -- Idempotent: reuse an existing active wearable grant to this doctor.
  select id into v_grant from access_grants
    where patient_id = v_patient
      and granted_to_type = 'doctor'
      and granted_to_id = p_doctor
      and type = 'wearable'
      and status = 'active'
      and revoked_at is null;
  if v_grant is not null then
    return v_grant;
  end if;

  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status)
    values (v_patient, 'doctor', p_doctor, 'wearable', 'active')
    returning id into v_grant;
  return v_grant;
end;
$$;

-- Patient: one-tap revoke a wearable share (filtered to type='wearable' so it
-- can never touch a clinical grant).
create or replace function carebridge_revoke_wearable(p_grant uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := current_patient_id();
  v_found   uuid;
begin
  if v_patient is null then
    raise exception 'not a patient session';
  end if;

  update access_grants
    set revoked_at = now(), status = 'revoked'
    where id = p_grant and patient_id = v_patient
      and type = 'wearable' and status = 'active'
    returning id into v_found;
  if v_found is null then
    raise exception 'no active wearable share to revoke for this patient';
  end if;
end;
$$;

grant execute on function carebridge_share_wearables(uuid) to authenticated;
grant execute on function carebridge_revoke_wearable(uuid) to authenticated;

-- Live-ish patient daily view: reflect metric changes in seconds. RLS still
-- runs per streamed row (patients see only their own).
alter publication supabase_realtime add table wearable_metrics_daily;
