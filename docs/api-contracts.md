# CareBridge — API / Edge Function Contracts

Status legend: **STUB** = folder + 501 placeholder exists; wired in the noted phase.

## `mint-scope-token` — STUB (Phase 2, D2)

Mints a short-lived scoped JWT after clinic login + PIN entry (D1).

- **Request:** `{ clinic_id, target_role: "doctor"|"admin", target_doctor_id?: uuid, pin }`
- **Server:** verify `pin` against `doctors.pin_hash` / `clinics.admin_pin_hash`
  (hashed, rate-limited); on success sign a JWT with custom claims:
  `{ clinic_id, active_role, active_doctor_id }` (TTL 30–60 min).
- **Response:** `{ access_token, expires_at }`
- **Secrets:** `SUPABASE_JWT_SECRET` (server-only).
- RLS reads these claims; client app state is never trusted.

## `ai-summary` — STUB (Phase 7, §8)

One-touch summary. Claude API server-side only.

- **Input:** ONLY structured visit + test-result data (never raw notes/OCR/images).
- **Output:** `{ "summary": "...", "sentence_sources": [{ "sentence": "...", "visit_id"|"test_order_id": "..." }] }`
- **Safety:** summarize-only, never diagnosis/treatment under any prompt variation.
  Function MUST validate every returned source id against the actual input set and
  **drop hallucinated references** (D6) before responding.
- **Secrets:** `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` (default `claude-sonnet-4-6`).

## `notifications` — STUB (Phase 8)

Scheduled reminders + report-ready pushes via FCM. Medication times derive from
the D5 `prescriptions.schedule` booleans.

- **Secrets:** `FCM_SERVER_KEY`, `FCM_PROJECT_ID`.
