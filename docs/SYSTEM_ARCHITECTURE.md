# CareBridge — System Architecture (as built, 2026-07-04)

> Audit Phase 3 deliverable. Describes what EXISTS. CLAUDE.md remains the
> product spec; DECISIONS.md holds settled decisions. Where implementation
> diverges from the spec, see the Phase 1.5 drift report — this file records
> reality, it does not re-decide anything.

## 1. Topology

```
Flutter app (single codebase: iOS / Android / Web)
 ├─ role-routed from a three-button entry: Patient / Hospital / Diagnostic Partner
 ├─ state: flutter_riverpod; navigation: go_router
 └─ talks ONLY to Supabase with the publishable (anon) key + the user's JWT
        │
Supabase project
 ├─ Postgres + RLS  ← every access decision lives here
 ├─ GoTrue auth (asymmetric-signed JWTs + custom access-token hook)
 ├─ Storage: private 'reports' bucket (policy-gated files)
 ├─ Edge Functions (Deno):
 │   ├─ mint-scope-token  — clinic register/login/scope (service role inside)
 │   ├─ ai-summary        — one-touch summary; calls the LLM server-side
 │   └─ notifications     — cron-driven queue dispatcher → FCM v1
 └─ pg_cron: 'carebridge-notifications' every 10 min (created out-of-band;
     embeds CRON_SECRET, deliberately not in committed migrations)

External services: Groq API (LLM, server-side only) · Firebase FCM (push)
Pending (Phase 11): ABDM / HPR / HFR registries, real SMS OTP.
```

## 2. Identity model (three tracks, intentionally asymmetric)

| Role | GoTrue user | Scoping |
|---|---|---|
| Patient | 1 user ↔ `patients.auth_user_id` | `current_patient_id()` from `auth.uid()` |
| Hospital/clinic | 1 service-provisioned user per clinic (`clinics.auth_user_id`); password lives ENCRYPTED in Vault, service-role-readable only | Scope (doctor vs admin) chosen after a bcrypt PIN (D1), written server-side to `scope_sessions`, injected into the JWT by `custom_access_token_hook` (D2). RLS reads `clinic_id` / `active_role` / `active_doctor_id` claims. |
| Diagnostic partner | 1 user ↔ `diagnostic_partners.auth_user_id` | `current_partner_id()`; flat, no picker (Section 2.3) |

Clinic login flow: `register`/`login` (Edge Function, rate-limited per IP,
registered-phone second factor until real OTP) → adopt GoTrue session →
pick identity → PIN verified server-side (`carebridge_verify_pin`, 5 strikes /
15-min lock) → `scope_sessions` upsert → client refreshes session → new token
carries the scope claims. Switching identity = new PIN + refresh; no
client-side role flipping is possible.

## 3. The trust core (Section 7) — where each rule is enforced

- **Grant checks**: `current_scope_can_view_patient()` (SECURITY DEFINER,
  pinned search_path) — doctor scope needs its own active grant; admin scope
  inherits via ANY doctor of its clinic (AC-8). Used by every clinical-table
  policy.
- **Writes** (visits/prescriptions/test orders): policies demand
  `active_role='doctor' AND active_doctor_id IS NOT NULL` and writing under
  one's own id (AC-9).
- **Grant lifecycle**: client-write-locked; all mutations via
  `carebridge_*` definer functions (consent codes Flow A, request/respond
  Flow B, revoke, order-scoped Flow C).
- **Flow C**: partner data access is FUNCTION-ONLY narrow columns (name + the
  one ordered test); order-scoped grant auto-closes on report upload or 30-day
  expiry; open orders grant nothing until claimed.
- **Files**: private `reports` bucket; storage policies parse the order id
  from the object path (`<order_id>/<file>`, always `objects.name`-qualified)
  and reuse the same grant rules. Viewers use short-lived signed URLs whose
  creation itself passes the SELECT policies.
- **Audit**: `access_logs` is client-immutable, patient-readable, and written
  on record-open, AI-summary view, and Flow C claim — distinguishing
  doctor / clinic_admin / diagnostic_partner.
- **Paid tier (Section 9)**: `current_clinic_is_paid()` gates AI summary and
  follow-up reminders IN THE DB; UI gating is cosmetic on top.

## 4. Data-flow pipelines

**AI summary (Section 8, two layers).** Layer 1 (allergies / chronic /
medications chips) renders straight from `patients` structured fields — never
LLM-generated. Layer 2: Flutter → `ai-summary` (caller JWT) →
`carebridge_ai_summary_input()` assembles STRUCTURED-ONLY input (visit
free-text notes and file reports are excluded at the database), string fields
clipped/sanitized → fingerprint checked against the `ai_summaries` cache
(service-write-only) → on miss, Groq (`llama-3.3-70b-versatile`, JSON mode)
with the exact Section 8 system prompt → returned `sentence_sources` are
validated against real input ids (hallucinated refs dropped) → cached +
returned under the mandatory verify label. Provider switch to the Claude API
is a secrets change (`ANTHROPIC_API_KEY` wins if set), no code change.
No patient identifiers (name/phone/ABHA) are sent to the LLM; diagnoses and
medications are — flagged for DPDP cross-border review (register M4).

**Notifications (Phase 8).** Enqueue happens AT THE DATABASE: appointment
trigger (24 h before), follow-up trigger (9 am on the date), report-ready
inside `carebridge_upload_report`, one-tap follow-up reminders via definer
function (paid). Medication reminders are computed per IST slot
(08/14/20 h) from active D5 prescription schedules by the dispatcher and
deduped per patient/slot/day. The `notifications` Edge Function (CRON_SECRET
header only) dispatches due rows: FCM v1 via service-account JWT
(`FCM_SERVICE_ACCOUNT_B64`), generic PHI-free push text; the in-app feed
(patient-RLS rows) works with or without FCM.

**Diagnostics (Flow C).** Doctor orders (definer fn, AC-9) → assigned order
grants the named partner immediately, open order grants on claim-by-code →
partner updates progress (sample_collected/in_progress only) → uploads file
to Storage (grant-gated path) then records the report → order flips
report_ready, grant closes, patient notification enqueued.

**Live queue (Phase 10, paid).** `appointments` is in the Realtime
publication; RLS decides which change events a session receives (doctor =
own rows, admin = clinic-wide, patient = self). Events are SIGNALS — the UI
refetches `carebridge_live_queue()` (narrow columns: patient name + token
only). Check-in (`carebridge_checkin_appointment`, per-doctor-per-day
sequential tokens, doctor or front-desk admin) and `carebridge_call_next`
(doctor-only) are PAID-gated in the DB; viewing booked appointments stays
free-tier.

## 5. State management & test seams

Every feature follows the same pattern: abstract repository + Supabase
implementation + Riverpod `Provider`, overridden with fakes in widget tests.
Repositories NEVER decide visibility — they ride the scoped JWT and let RLS
filter. Side-effect seams (`VoiceInput` over speech_to_text) exist so tests
run without devices. Trust rules are re-proven at the SQL layer by six
harnesses under `supabase/tests/` (each a single DO block that seeds, asserts
across scopes via `set_config('request.jwt.claims', …)`, and rolls back via a
success-marker RAISE — exit code 1 with `*_OK` is a PASS).

## 6. External service contracts

| Service | Contract | Secrets (server-side only) |
|---|---|---|
| Supabase | PostgREST + RPC + Storage + GoTrue; anon key in `app/.env` (client-safe); service key / DB URL in root `.env` (gitignored) | `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, `SUPABASE_ACCESS_TOKEN` |
| Groq | OpenAI-compatible `chat/completions`, JSON mode, temperature default; treat output as untrusted (defensive parse + source-id validation) | `GROQ_API_KEY` |
| FCM | HTTP v1 `messages:send`; OAuth2 RS256 from service account | `FCM_SERVICE_ACCOUNT_B64` |
| Scheduler | pg_cron → pg_net POST with `x-cron-secret` | `CRON_SECRET` |
| ABDM/HPR/HFR | NOT integrated (Phase 11); placeholder auth flagged in-UI | — |

## 7. Known-pending (not defects)

Phase 11 real auth (ABDM patient OTP, clinic
SMS OTP, partner lab-registry, HPR verification badges), payment gateway
(Section 9 stub), in-app PDF renderer (signed-URL link today), Android
emulator / iOS TestFlight builds. Risk-register items H1/H2 carry interim
mitigations (phone second factor, unverified badge, IP rate limits) until
Phase 11 replaces them.
