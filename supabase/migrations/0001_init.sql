-- CareBridge — initial schema (Phase 1)
-- Section 6 of CLAUDE.md, with the D1–D5 amendments from DECISIONS.md folded in.
-- RLS is ENABLED in 0002; full policy bodies are authored in later phases (see notes there).

create extension if not exists pgcrypto;   -- gen_random_uuid(), gen_random_bytes()

-- ============================================================
-- Enums
-- ============================================================
create type subscription_status as enum ('free', 'paid');
create type diagnostic_type      as enum ('lab', 'imaging', 'both');
create type test_status          as enum ('ordered', 'sample_collected', 'in_progress', 'report_ready', 'cancelled');
create type report_type          as enum ('pdf', 'image', 'structured');

-- D4: one_time stays in the enum but is RESERVED/UNUSED in MVP.
create type grant_type           as enum ('standing', 'one_time', 'order_scoped');
create type grant_target_type    as enum ('doctor', 'diagnostic_partner');
create type grant_status         as enum ('active', 'revoked', 'expired', 'pending');

-- accessor type for audit log (distinguishes clinic_admin per Section 10 auditability)
create type accessor_type        as enum ('doctor', 'clinic_admin', 'diagnostic_partner');

-- D5: structured prescription scheduling
create type food_relation        as enum ('before', 'after', 'with', 'none');

-- D2: scope claims live in the JWT, not a table — but we mirror the role enum for clarity.
create type active_role          as enum ('doctor', 'admin');

-- ============================================================
-- Core entities
-- ============================================================

-- D3: abha_id is NULLABLE for the pilot; phone is the practical key until ABHA links.
create table patients (
  id                  uuid primary key default gen_random_uuid(),
  abha_id             text unique,                       -- nullable (D3)
  name                text not null,
  dob                 date,
  phone               text not null unique,
  allergies           text[] not null default '{}',
  chronic_conditions  text[] not null default '{}',
  current_medications text[] not null default '{}',
  created_at          timestamptz not null default now()
);

create table clinics (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  registration_number text not null unique,              -- ID-3 mandatory
  hfr_id              text,                              -- optional
  address             text,
  login_credential    text,                              -- one credential per clinic (placeholder auth P1)
  admin_pin_hash      text,                              -- D1: admin identity PIN (hashed)
  subscription_status subscription_status not null default 'free',
  created_at          timestamptz not null default now()
);

-- every doctor belongs to a clinic; a solo practitioner is a clinic of one.
create table doctors (
  id                  uuid primary key default gen_random_uuid(),
  clinic_id           uuid not null references clinics(id) on delete restrict,
  name                text not null,
  council_reg_number  text not null,                     -- ID-4
  council_name        text not null,
  specialty           text not null,                     -- ID-4 (new field)
  hpr_id              text,                              -- optional, never block on it
  hpr_verified        boolean not null default false,    -- "Verified" badge once council confirms
  pin_hash            text,                              -- D1: per-doctor PIN (hashed)
  is_active           boolean not null default true,     -- deactivate, never hard-delete
  created_at          timestamptz not null default now()
);
create index idx_doctors_clinic on doctors(clinic_id);

create table diagnostic_partners (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  type                diagnostic_type not null,
  registration_number text not null unique,              -- ID-5 mandatory
  hfr_id              text,                              -- optional
  nabl_accredited     boolean,                           -- optional badge
  address             text,
  created_at          timestamptz not null default now()
);

-- ============================================================
-- Clinical records
-- ============================================================
create table visits (
  id                 uuid primary key default gen_random_uuid(),
  patient_id         uuid not null references patients(id) on delete restrict,
  doctor_id          uuid not null references doctors(id) on delete restrict,  -- AC-9: always a specific doctor
  clinic_id          uuid not null references clinics(id) on delete restrict,
  visit_date         timestamptz not null default now(),
  diagnosis          text,
  notes              text,
  follow_up_date     date,
  follow_up_completed boolean not null default false,
  created_at         timestamptz not null default now()
);
create index idx_visits_patient on visits(patient_id);
create index idx_visits_doctor  on visits(doctor_id);
create index idx_visits_clinic  on visits(clinic_id);

-- D5: structured schedule replaces loose frequency/duration text.
create table prescriptions (
  id               uuid primary key default gen_random_uuid(),
  visit_id         uuid not null references visits(id) on delete cascade,
  drug_name        text not null,
  dosage           text,
  schedule         jsonb not null default '{"morning":false,"afternoon":false,"night":false}'::jsonb,
  relation_to_food food_relation not null default 'none',
  duration_days    int,
  instructions     text,                                -- optional free text, NOT used for scheduling
  created_at       timestamptz not null default now()
);
create index idx_prescriptions_visit on prescriptions(visit_id);

-- ============================================================
-- Diagnostics
-- ============================================================
-- order_code: unguessable random token (grants order-scoped access when scanned).
create table test_orders (
  id                    uuid primary key default gen_random_uuid(),
  patient_id            uuid not null references patients(id) on delete restrict,
  doctor_id             uuid not null references doctors(id) on delete restrict,
  visit_id              uuid references visits(id) on delete set null,
  diagnostic_partner_id uuid references diagnostic_partners(id) on delete set null, -- null = open order
  test_type             text not null,
  test_name             text not null,
  status                test_status not null default 'ordered',
  order_code            text not null unique default encode(gen_random_bytes(16), 'hex'),
  created_at            timestamptz not null default now()
);
create index idx_test_orders_patient on test_orders(patient_id);
create index idx_test_orders_partner on test_orders(diagnostic_partner_id);
create unique index idx_test_orders_code on test_orders(order_code);

create table test_reports (
  id                uuid primary key default gen_random_uuid(),
  test_order_id     uuid not null references test_orders(id) on delete cascade,
  report_type       report_type not null,
  file_url          text,                               -- pdf/image (Supabase Storage), gated by grant logic
  structured_values jsonb,                              -- pathology numeric values / flags
  uploaded_by       uuid not null references diagnostic_partners(id) on delete restrict,
  uploaded_at       timestamptz not null default now()
);
create index idx_test_reports_order on test_reports(test_order_id);

-- ============================================================
-- Scheduling
-- ============================================================
create table appointments (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references patients(id) on delete restrict,
  doctor_id      uuid not null references doctors(id) on delete restrict,
  clinic_id      uuid not null references clinics(id) on delete restrict,
  scheduled_time timestamptz not null,
  status         text not null default 'scheduled',
  queue_position int,
  created_at     timestamptz not null default now()
);
create index idx_appointments_doctor on appointments(doctor_id);
create index idx_appointments_clinic on appointments(clinic_id);

-- ============================================================
-- Consent / access-grant model (Section 7) — the core trust mechanism
-- ============================================================
create table access_grants (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references patients(id) on delete cascade,
  granted_to_type grant_target_type not null,
  granted_to_id   uuid not null,                        -- doctor.id OR diagnostic_partner.id
  type            grant_type not null,                  -- D4: Flow A & B both default 'standing'
  test_order_id   uuid references test_orders(id) on delete cascade, -- set only for order_scoped (Flow C)
  status          grant_status not null default 'active',
  granted_at      timestamptz not null default now(),
  expires_at      timestamptz,
  revoked_at      timestamptz
);
create index idx_grants_patient on access_grants(patient_id);
create index idx_grants_target  on access_grants(granted_to_type, granted_to_id);
create index idx_grants_order   on access_grants(test_order_id);

-- Audit log — immutable, patient-queryable (Section 10). Distinguishes accessor type.
create table access_logs (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients(id) on delete cascade,
  accessed_by_type accessor_type not null,
  accessed_by_id   uuid not null,
  viewed_at        timestamptz not null default now(),
  what_viewed      text
);
create index idx_logs_patient on access_logs(patient_id);

create table notifications (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references patients(id) on delete cascade,
  type          text not null,
  payload       jsonb,
  scheduled_for timestamptz,
  sent_at       timestamptz,
  created_at    timestamptz not null default now()
);
create index idx_notifications_patient on notifications(patient_id);
