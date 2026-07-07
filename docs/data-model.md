# Ayulekha — Data Model Reference

Authoritative SQL lives in `supabase/migrations/`. This doc is the human-readable
companion, reflecting Section 6 of `CLAUDE.md` **with the D1–D5 amendments** from
`DECISIONS.md` applied.

## Amendments applied vs. CLAUDE.md §6

| # | Change | Source |
|---|--------|--------|
| D1 | `doctors.pin_hash`, `clinics.admin_pin_hash` added (per-identity PINs, hashed) | DECISIONS D1 |
| D2 | Scope claims (`clinic_id`, `active_role`, `active_doctor_id`) live in the JWT, **not** a table | DECISIONS D2 |
| D3 | `patients.abha_id` is **nullable**; `patients.phone` is the practical key | DECISIONS D3 |
| D4 | `access_grants.type` enum keeps `one_time` but it is **reserved/unused** in MVP | DECISIONS D4 |
| D5 | `prescriptions` uses `schedule jsonb` + `relation_to_food` + `duration_days` (replaces loose freq/duration text) | DECISIONS D5 |

## Tables (summary)

- **patients** — owner of the record. `abha_id` nullable (D3).
- **clinics** — one login credential; `admin_pin_hash` (D1); `subscription_status` free|paid (§9).
- **doctors** — `clinic_id NOT NULL` (solo = clinic of one); `specialty`; `hpr_id` nullable + `hpr_verified`; `pin_hash` (D1); `is_active` (soft-delete).
- **diagnostic_partners** — flat; `registration_number` mandatory; optional `hfr_id`, `nabl_accredited`.
- **visits** — always tied to a specific `doctor_id` (AC-9).
- **prescriptions** — structured `schedule`/`relation_to_food`/`duration_days` (D5).
- **test_orders** — `order_code` = unguessable random token (`gen_random_bytes`); `diagnostic_partner_id` null = open order.
- **test_reports** — pdf|image (Storage `file_url`) or structured numeric values.
- **appointments** — queue/token tracking.
- **access_grants** — the trust core (§7). `type` standing|one_time(reserved)|order_scoped; `test_order_id` set only for order-scoped (Flow C).
- **access_logs** — immutable audit; `accessed_by_type` distinguishes doctor / clinic_admin / diagnostic_partner (§10).
- **notifications** — appointment/medication/follow-up/report-ready.

## RLS posture (Phase 1)

`0002_rls_enable.sql` enables RLS on every table (default-deny) and adds the
claim-reader helpers `current_clinic_id()`, `current_active_role()`,
`current_active_doctor_id()`. Full policy **bodies** are authored in:

- **Phase 2** — doctor-scoped vs admin-scoped read/write; AC-9 write gating.
- **Phase 5** — AC-8 admin inherited visibility + Flow A/B grant checks.
- **Phase 6** — AC-10 order-scoped diagnostic grants (Flow C) + matching Storage policies.
