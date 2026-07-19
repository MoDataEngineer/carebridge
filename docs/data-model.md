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

## Update 2026-07-19 (migrations 0024–0030)

| Table / object | Change | Migration |
|---|---|---|
| `doctor_sessions` | NEW — weekly availability: `doctor_id`, `day_of_week` (0=Sun), `label`, `start_time`, `end_time`, `capacity`, `is_active`. Patients book INTO a session. | 0025 |
| `appointments.session_id` | NEW FK → doctor_sessions. Booking within capacity → `scheduled`; overflow → `requested` (doctor approves/declines). One ACTIVE booking per patient/session/day (dedupe). | 0026, 0029 |
| `notifications` | Added to the `supabase_realtime` publication (live bell badge + chime); queue events (`checked_in`, `your_turn`, `appointment_approved`, `appointment_rejected`) enqueued server-side. | 0024, 0027 |
| `diagnostic_partners` | NEW `phone`, `pin_hash`, `verified` — real flat login (reg number + PIN, bcrypt + lockout via the `partner` identity type). GoTrue password in Vault (`partner_password:<id>`). | 0028 |
| `doctors.photo_url`, `clinics.logo_url` | NEW — branding. Public `branding` storage bucket; `carebridge_bookable_doctors` returns both; `carebridge_set_branding(doctor,url)` RPC. Uploads go through the `branding-upload` edge function (service role) — client-side storage RLS is unreliable on this project (403 even under permissive policies). | 0030 |

Key RPCs added: `carebridge_now_serving`, `carebridge_set_doctor_sessions`,
`carebridge_available_sessions`, `carebridge_request_appointment`,
`carebridge_upcoming_appointments` (returns `patient_phone`),
`carebridge_approve_appointment`, `carebridge_reject_appointment`,
`carebridge_set_branding`.
