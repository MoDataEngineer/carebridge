-- CareBridge — enable RLS + scope-claim helpers (Phase 1)
-- D2: app state is NEVER trusted for access decisions. RLS reads scope claims from the
-- short-lived JWT minted by the mint-scope-token Edge Function (Phase 2).
--
-- PHASE 1 POSTURE: default-deny everywhere + the claim-reader helpers below.
-- The actual grant-checking policy BODIES are authored in the phases that make them testable:
--   * Phase 2 — doctor-scoped vs admin-scoped read/write on patients/visits/prescriptions
--   * Phase 5 — AC-8 admin inherited visibility + Flow A/B grant checks
--   * Phase 6 — AC-10 order-scoped diagnostic-partner grants (Flow C) + Storage policies
-- Each is marked TODO-by-phase so nothing is silently skipped.

-- ============================================================
-- Scope-claim helper functions (read D2 JWT custom claims)
-- ============================================================
create or replace function current_clinic_id() returns uuid
  language sql stable as $$
    select nullif(auth.jwt() ->> 'clinic_id', '')::uuid
  $$;

create or replace function current_active_role() returns text
  language sql stable as $$
    select auth.jwt() ->> 'active_role'      -- 'doctor' | 'admin'
  $$;

create or replace function current_active_doctor_id() returns uuid
  language sql stable as $$
    select nullif(auth.jwt() ->> 'active_doctor_id', '')::uuid
  $$;

-- ============================================================
-- Enable RLS on every table (default-deny until policies land)
-- ============================================================
alter table patients            enable row level security;
alter table clinics             enable row level security;
alter table doctors             enable row level security;
alter table diagnostic_partners enable row level security;
alter table visits              enable row level security;
alter table prescriptions       enable row level security;
alter table test_orders         enable row level security;
alter table test_reports        enable row level security;
alter table appointments        enable row level security;
alter table access_grants       enable row level security;
alter table access_logs         enable row level security;
alter table notifications       enable row level security;

-- With RLS enabled and no policies, all access is denied by default for non-service roles.
-- service_role (migrations, Edge Functions) bypasses RLS as intended.

-- ------------------------------------------------------------
-- TODO (Phase 2): patients/visits/prescriptions read+write policies keyed on
--   current_active_doctor_id() / current_active_role() / current_clinic_id().
--   Guarantee (b): a doctor-scoped session sees ONLY rows tied to its active_doctor_id.
--   Guarantee (c) / AC-8 (Phase 5): an admin-scoped session sees a patient iff an active
--   grant exists between that patient and ANY doctor in current_clinic_id().
--   AC-9: writes to visits/prescriptions require active_role='doctor' AND active_doctor_id IS NOT NULL.
-- TODO (Phase 6): test_orders/test_reports order-scoped grant policies (Flow C) — a partner
--   sees ONLY patient name + the specific ordered test, never visit history. Mirror in Storage.
-- ------------------------------------------------------------
