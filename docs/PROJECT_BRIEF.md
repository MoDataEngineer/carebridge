# Project Brief: Ayulekha — Patient–Clinic–Diagnostics Health Record Platform

> Save this file as BOTH `CLAUDE.md` and `AGENTS.md` in the repo root.
> Claude Code reads `CLAUDE.md` automatically. Codex reads `AGENTS.md`.
> Same content, two filenames — keep them in sync if you edit one.
> This is the authoritative, complete spec. If anything below is ambiguous when you reach it, stop and ask rather than guessing.

## 1. What this app is

A single app/web platform, one GitHub repo, for India's healthcare ecosystem, with three entry-point roles:

- **Patient** — owns a portable medical record (ABHA-linked) that travels across clinics and labs, with their consent.
- **Doctor / Clinic** — a clinic account that can hold one or many doctors. Doctors get an efficiency toolkit (paid tier) — live queue, one-touch AI summary, follow-up tracking, in-app diagnostics.
- **Diagnostic Partner** — labs/imaging centers that receive digital test orders and upload results straight into the app.

Built solo, non-technical founder, single GitHub repo, single Flutter codebase.

## 2. Entry screen & identity model — READ THIS SECTION CAREFULLY, IT GOVERNS EVERYTHING ELSE

The app opens with **three buttons, nothing else**: **Patient / Doctor / Diagnostic Partner**. There is no literal "Clinic" button — "Doctor" is the entry point that leads into the clinic/doctor structure below.

### 2.1 Patient
Standard individual account. Login via ABHA ID (Section 4).

### 2.2 Doctor → leads to a CLINIC-level login, which may hold multiple doctors
This is the most important structural decision in this spec — read it twice before coding.

- Tapping "Doctor" takes you to a **clinic login/registration** screen (clinic registration/license number + phone/OTP).
- A clinic is created once, and **doctors are added under it** — not the other way around. A solo practitioner is simply a clinic with exactly one doctor.
- **Registering a doctor under a clinic requires:** doctor name, medical council registration number, council name, **specialty** (new field), and optional HPR ID.
- **After clinic login, session scoping works like this:**
  - If the clinic has exactly **one** doctor → skip any picker. That session is automatically scoped as **both** that doctor **and** the clinic admin (solo practitioner = admin + sole doctor, no extra step).
  - If the clinic has **two or more** doctors → show a **"Who are you?"** screen: a list of doctor names to tap, plus a **"Clinic Admin / View All"** option.
    - Tapping a doctor name → session is **doctor-scoped**: sees and acts only on that doctor's own patients (own queue, own visits, own follow-ups, own patient search results).
    - Tapping "Clinic Admin / View All" → session is **admin-scoped**: sees every patient across every doctor in the clinic, and manages the doctor roster (add/edit/deactivate a doctor — name, council reg number, council name, specialty, optional HPR).
  - There is **one login credential per clinic**, not one per doctor. The "Who are you?" screen is a session-scoping choice made *after* a successful clinic login, not a second password.
- **Default rule (deliberate design choice, confirmed with founder):** when a patient grants record access to one doctor at a clinic, the **clinic admin automatically inherits visibility into that same patient's record** too — no separate consent step required for the admin. The access-grant check for an admin-scoped session is: "does an active grant exist between this patient and **any** doctor in this clinic?" rather than checking one specific doctor_id. (See AC-8 in Section 7.)
- **Clinical accountability default (also a deliberate choice, flag this to the founder if it ever needs revisiting):** writing a diagnosis or prescription always requires the session to be scoped to a *specific* doctor identity, never a bare "admin" identity with no doctor attached. A solo practitioner's session is both admin and doctor simultaneously, so this is naturally satisfied. In a multi-doctor clinic, pure administrative staff using "Clinic Admin / View All" can view everything but should not write clinical notes under a generic admin identity — keep that action gated to a selected doctor.

### 2.3 Diagnostic Partner
**Stays flat — no nested staff identification.** One login per lab/imaging center (registration/license number, optional HFR ID and NABL accreditation). This asymmetry with the clinic structure above is intentional, not an oversight.

## 3. Tech stack (decided — do not re-litigate without discussion)

- **Frontend: Flutter.** ONE codebase compiles to iOS, Android, AND Web.
  - Patient app: mobile only (iOS + Android).
  - Doctor/Clinic app: full feature parity on mobile AND web.
  - Diagnostic partner portal: same codebase, web-primary, mobile-capable.
  - Role-based routing from the three-button entry screen (Section 2) determines which flow loads. Responsive layout (`LayoutBuilder`/breakpoints) reflows the same widgets by screen size — do not fork into separate codebases per role or platform.
- **Backend: Supabase** (Postgres + Auth + Storage + Realtime + Edge Functions).
  - Row-Level Security (RLS) enforces the access-grant model (Section 7) at the database level, including the admin-inherits-visibility rule and the order-scoped grant type for diagnostic partners.
  - **File storage:** Supabase Storage holds uploaded lab PDFs and scan/X-ray images. Storage access must be gated by the same access-grant logic as database rows — signed URLs or storage-level policy, never just an app-layer check.
- **Push notifications:** Firebase Cloud Messaging.
- **AI summary generation:** Claude API, called server-side only from a Supabase Edge Function. Never call it directly from the Flutter client.
- **Report viewing:** in-app PDF and image viewer components.
- **Repo:** single GitHub repo, monorepo layout (Section 3.1).

### 3.1 Repository structure

```
/app                    Flutter project (single codebase: patient + doctor/clinic + diagnostic partner, mobile + web)
/supabase
  /migrations           SQL schema (Section 6 tables)
  /functions
    ai-summary/         Edge function: calls Claude API for one-touch summary
    notifications/      Edge function: scheduled reminders + report-ready notifications
/docs
  PROJECT_BRIEF.md       (this file)
  data-model.md
  api-contracts.md
CLAUDE.md                copy of this file
AGENTS.md                copy of this file
```

## 4. Identity & onboarding requirements

| ID | Requirement |
|---|---|
| ID-1 | Patient registration requires a valid ABHA ID; no ABHA, no account. |
| ID-2 | If a patient has no ABHA ID, offer an inline "Create ABHA" flow (Aadhaar OTP or mobile-based) without leaving the app. |
| ID-3 | Clinic registration requires clinic registration/license number (mandatory) + optional HFR ID. One login credential per clinic. |
| ID-4 | Each doctor added under a clinic requires: name, medical council registration number, council name, specialty. HPR ID optional/linked — never block on it (3–5 day council verification). "Verified" badge once confirmed. |
| ID-5 | Diagnostic partner registration requires a lab/diagnostic registration or license number (mandatory) + optional HFR ID + optional NABL accreditation badge. Flat login, no nested staff. |
| ID-6 | The platform must never store a patient's, clinic's, doctor's, or diagnostic partner's raw Aadhaar number in its own database. |

## 5. Feature list by role

### 5.1 Patient app (mobile, iOS + Android)
- ABHA login/signup with inline create-ABHA flow
- Profile: allergies, chronic conditions, current medications (structured fields)
- Book appointment; view own visit history (read-only): diagnosis, prescriptions, doctor notes
- Generate a share QR/code for in-person doctor visits (Flow A, Section 7)
- Approve/deny a remote doctor's access request (Flow B, Section 7)
- "Doctors with access" — view and one-tap revoke any active grant
- "Who viewed my records" — plain-language access log
- **Tests tab:** status of ordered tests, order code/QR to show at a diagnostic partner, in-app viewer for completed reports (PDF/image/structured values) — no physical copies needed
- Push notifications: appointment reminders, medication reminders, report-ready notifications

### 5.2 Doctor/Clinic app (mobile + web, same codebase, full feature parity)
**Available regardless of session scope (doctor-scoped or admin-scoped):**
- Patient search by name/phone/ABHA — search-first, instant results (doctor-scoped: own patients only; admin-scoped: all clinic patients)
- Patient profile, tabbed: Summary / History / Prescriptions / Tests / Notes

**Doctor-scoped session only (writing clinical data requires a specific doctor identity, per Section 2.2):**
- Add a visit: diagnosis, prescription (drug, dosage, frequency, duration, autocomplete + saved templates), optional follow-up date
- Order a lab/imaging test: select test type, optionally select a specific integrated diagnostic partner or leave open; system generates an order code/QR
- View completed lab values and scan/X-ray images or PDFs directly in the Tests tab
- Voice input for prescriptions, parsed into structured fields, always shown for doctor review/edit before saving (never auto-saved)
- Follow-up tracker: own patients due/overdue; one-tap reminder send
- Manage own availability/slots calendar
- Request access to a new patient's history (Flow B)
- Dashboard: live appointment/token tracker, scoped to that doctor's own queue

**Admin-scoped session only ("Clinic Admin / View All"):**
- View all patients across all doctors in the clinic (read access; cannot write clinical notes under the bare admin identity, per Section 2.2)
- Manage doctor roster: add doctor (name, council reg number, council name, specialty, optional HPR), edit, deactivate (soft-delete — preserve historical visit records)
- Clinic-wide live appointment/token tracker across all doctors
- Clinic subscription/billing status (Section 8)

### 5.3 Diagnostic Partner portal (web-primary, mobile-capable)
- Login via lab/diagnostic registration number; optional HFR ID and NABL accreditation link
- Scan or enter a patient's order code/QR to retrieve a specific test order
- On retrieving an order, view **only**: patient name, the specific test ordered, ordering doctor/clinic — never broader patient history (privacy-critical)
- Update order status: sample collected / scan done / in progress
- Upload result against the order: PDF/image for imaging, structured numeric values for pathology
- Once uploaded, the order-scoped access grant for that lab closes automatically

## 6. Data model (core tables)

```
patients
  id, abha_id, name, dob, phone,
  allergies text[], chronic_conditions text[], current_medications text[]

clinics
  id, name, registration_number, hfr_id (nullable), address,
  login_credential, subscription_status [free | paid]

doctors
  id, clinic_id NOT NULL,             -- every doctor belongs to a clinic; solo = clinic of one
  name, council_reg_number, council_name, specialty, hpr_id (nullable),
  is_active (bool, default true)      -- deactivate, don't hard-delete

diagnostic_partners
  id, name, type [lab | imaging | both],
  registration_number, hfr_id (nullable), nabl_accredited (bool, nullable),
  address

visits
  id, patient_id, doctor_id, clinic_id, visit_date,
  diagnosis, notes, follow_up_date (nullable), follow_up_completed (bool)

prescriptions
  id, visit_id, drug_name, dosage, frequency, duration, instructions

test_orders
  id, patient_id, doctor_id, visit_id,
  diagnostic_partner_id (nullable — null means "open", any partner can fulfill),
  test_type, test_name, status [ordered | sample_collected | in_progress | report_ready | cancelled],
  order_code, created_at

test_reports
  id, test_order_id, report_type [pdf | image | structured],
  file_url (nullable), structured_values (jsonb, nullable),
  uploaded_by (diagnostic_partner_id), uploaded_at

appointments
  id, patient_id, doctor_id, clinic_id, scheduled_time, status, queue_position (nullable)

access_grants
  id, patient_id, granted_to_type [doctor | diagnostic_partner],
  granted_to_id, type [standing | one_time | order_scoped],
  granted_at, expires_at (nullable), revoked_at (nullable), status,
  test_order_id (nullable — set only for order_scoped grants)

access_logs
  id, patient_id, accessed_by_type [doctor | clinic_admin | diagnostic_partner],
  accessed_by_id, viewed_at, what_viewed

notifications
  id, patient_id, type, payload, scheduled_for, sent_at
```

## 7. Consent / access-grant logic — the core trust mechanism, implement exactly this

**For a doctor-scoped session**, before returning a patient's visits/prescriptions:
1. Check `access_grants` for a row matching `(doctor_id, patient_id)` where `revoked_at IS NULL` and (`expires_at IS NULL OR expires_at > now()`).
2. If found → return data, log to `access_logs` with `accessed_by_type = doctor`.
3. If not found → trigger Flow A or Flow B below.

**For an admin-scoped session (AC-8, the deliberate inherited-visibility rule):**
- Check whether an active grant exists between the patient and **any** doctor belonging to that admin's clinic (not a specific doctor_id).
- If yes → admin may view, logged with `accessed_by_type = clinic_admin`.
- The patient is not asked to separately consent to the admin.

**Flow A — In-person (doctor):** patient generates a short-lived QR/code; doctor scanning it creates the grant immediately, type `standing` by default (no re-consent on future visits with that same doctor).

**Flow B — Remote/doctor-initiated:** doctor requests access by phone/ABHA lookup → patient approves/denies via push notification → grant created only on approval.

**Flow C — Diagnostic partner order-scoped grant:**
1. When a doctor creates a `test_orders` row, automatically create a matching `access_grants` row: `granted_to_type = diagnostic_partner`, `type = order_scoped`, linked to that `test_order_id`.
2. This grant permits viewing **only**: patient name, the specific test ordered, ordering doctor/clinic. Never the patient's visit history or anything else.
3. The grant closes automatically the moment a report is uploaded against that order, or after a fixed expiry (e.g. 30 days), whichever is first.
4. If a test order is left "open" (no specific `diagnostic_partner_id`), the grant is created only once a partner actually scans/claims the order code.

**Patient-facing screens (required):**
- "Doctors with access" — active grants, one-tap revoke.
- "Who viewed my records" — plain-language rendering of `access_logs`, distinguishing doctor / clinic admin / diagnostic partner access.
- "Tests" tab — order status + in-app report viewing.

**Access control must be enforced at the database level (RLS), not solely in application code — including the admin inherited-visibility check and the order-scoped grant type.**

## 8. One-touch AI summary — exact spec

**Two layers. Do not let the AI generate layer 1.**

**Layer 1 — deterministic safety banner (always visible, never AI-generated):** allergies, chronic conditions, current medications as chips from structured patient fields.

**Layer 2 — AI-generated narrative:**
- Input: ONLY structured fields — visits as `{date, diagnosis, prescriptions[], follow_up_date, follow_up_completed}`, plus structured test results/flags from `test_reports.structured_values` where available. Never raw free-text notes, OCR'd documents, or unparsed scan images.
- System prompt (Edge Function → Claude API):

  > "You are summarizing a patient's medical visit history for a doctor about to see them. Use ONLY the structured visit and test-result data provided below — do not infer, assume, or add anything not explicitly present. Write one short paragraph (3–5 sentences) covering: how many visits and over what period, the main recurring issue if any, current/most recent medication and since when, any notable structured test results, and whether a follow-up was advised and whether it happened. If data looks incomplete or contradictory, say so plainly instead of guessing. Do not suggest a diagnosis or treatment — only summarize what already happened."

- Output: `{"summary": "...", "sentence_sources": [{"sentence": "...", "visit_id" | "test_order_id": "..."}]}` — powers tap-to-source.
- Label: **"AI-generated summary — verify against full record."**
- Regenerate automatically whenever a new visit OR test report is added.
- Available to both doctor-scoped and admin-scoped sessions, subject to the access-grant check in Section 7.
- Compliance boundary: summarization only, never diagnosis or treatment suggestion, under any prompt variation.

## 9. Monetization / subscription gating (MVP-level structure only)

- `clinics.subscription_status` is `free` or `paid`. No real payment gateway integration required for MVP — a manually-set flag (admin-settable or founder-settable via Supabase dashboard) is sufficient for now; stub an "Upgrade" screen for later Razorpay/Stripe-style integration.
- **Free tier:** core record-keeping, appointment booking, basic visit/prescription entry, diagnostic test ordering.
- **Paid tier gates:** live appointment/token tracker, one-touch AI summary, follow-up tracker, no-show automated reminders, voice prescription input, prescription templates/autocomplete.
- Diagnostic partners and patients are never charged in MVP.

## 10. Non-functional requirements

| Category | Requirement |
|---|---|
| Security | Encryption at rest and in transit for all patient data, including uploaded lab/scan files. No raw Aadhaar storage anywhere. API keys never shipped client-side. |
| Compliance | Design within India's DPDP Act and ABDM consent framework. Confirm record retention rules with a healthcare compliance advisor before real launch. |
| Auditability | Access logs are immutable and queryable by the patient at any time, distinguishing doctor / clinic admin / diagnostic partner access. |
| Performance | Live queue/token updates reflect within a few seconds (real-time, not polling). |
| Scalability | Data model supports many clinics (each with many doctors), many diagnostic partners, per patient, from day one. |
| Platform parity | Doctor/clinic app must have identical functionality on mobile and web; single codebase, responsive layout. |
| File storage security | Object/file storage access must be gated by the same access-grant logic as database rows. |
| AI safety | AI summary is restricted to retrieval/summarization; must never produce diagnostic or treatment suggestions. |
| Clinical accountability | Writing diagnosis/prescriptions always requires a session scoped to a specific doctor identity, never a bare admin identity (Section 2.2). |

## 11. Build phasing — build in this order, pause for review between phases

1. **Scaffold:** Flutter app shell with the three-button entry screen (Section 2); Supabase schema (Section 6); placeholder auth for all three roles.
2. **Clinic/doctor session architecture:** clinic login, doctor roster (add/edit/deactivate), the "Who are you?" picker, solo-practitioner auto-scoping, doctor-scoped vs admin-scoped permission boundaries. Get this right before building features on top of it — it's the foundation everything else in the doctor app depends on.
3. **Patient core:** profile, appointment booking, read-only history view.
4. **Doctor core:** patient search (scoped correctly per Section 5.2), add visit + prescription, basic history view.
5. **Access-grant + consent flow** (Flows A & B, plus the admin inherited-visibility rule AC-8). Write tests for this specifically — it's the core trust mechanism, and the admin-visibility rule is easy to get subtly wrong.
6. **Diagnostic partner integration:** test ordering, order-scoped grants (Flow C), diagnostic partner portal, report upload, in-app report viewing.
7. **One-touch AI summary**, including structured test results as input.
8. **Notifications:** appointment, medication, follow-up, and report-ready reminders via FCM.
9. **Follow-up tracker, voice prescription input, prescription templates/autocomplete, subscription gating (Section 9).**
10. **Live appointment/token tracker** (Supabase Realtime), both doctor-scoped and clinic-wide admin view.
11. **Real ABHA/HPR/HFR API integration**, replacing placeholder auth.

## 12. Standing instructions for the coding agent

- Build one phase at a time per Section 11. Stop and summarize after each phase before continuing.
- Section 2 and Section 7's admin-inherited-visibility rule are the two places most likely to be implemented subtly wrong — re-read them before writing the relevant code, and write explicit tests for: (a) a solo doctor never seeing a "who are you" screen, (b) a doctor-scoped session never seeing another doctor's patients, (c) an admin-scoped session correctly seeing a patient if ANY doctor in the clinic has a grant, even if the admin personally never requested one.
- Ask before adding any new major dependency or paid third-party service.
- Never hardcode API keys or secrets — use environment variables / Supabase secrets manager.
- Enforce every access-grant and session-scoping check at the database level via RLS, not only in application code.
- Keep one Flutter codebase — do not fork separate web/mobile/role-specific projects.
- Flag clearly (don't silently skip) anything depending on credentials/APIs not yet available (ABDM sandbox keys, Claude API key, FCM config) — stub it and note what's needed to make it real.
- If anything in this spec seems contradictory or underspecified once you're implementing it, stop and ask the founder rather than guessing — several decisions here (admin inherited visibility, clinical-accountability gating) were explicit judgment calls, not arbitrary defaults, and silently reinterpreting them could break the trust model the whole app depends on.

## 13. Wearables & vitals module (PLANNED epic — Phases 12+, D14)

> Planned, not built. Authoritative design record: `docs/EPIC_wearables.md`
> (decision `DECISIONS.md` D14, 2026-07-23).

Patients connect a fitness band / smartwatch and get a standalone, always-free
**Strava-style daily fitness tracker** (steps, calories, active minutes,
workouts, sleep, heart rate, streaks, goals) — useful even if never shared. When
the patient chooses to share, the doctor gets a **paid**, per-patient trend +
**adherence** view that ties wearable data to a prior visit's advice
("did the patient follow it / did they improve").

- **Roles.** Patient view free & standalone; doctor view paid & consent-gated
  (Section 9). Diagnostic partner: out of scope. **Clinic admin (AC-8) does NOT
  auto-inherit wearable visibility** — stricter than clinical visit data.
- **Consent (Section 7 extension).** A NEW, separate, revocable grant scope
  `wearable`, **patient-initiated** (a "Share vitals" toggle per doctor), never
  automatic, logged in `access_logs` as `what_viewed = 'wearable data'`, gated by
  its own visibility helper (a plain clinical grant must not confer vitals
  access).
- **Integration.** On-device **Apple HealthKit + Android Health Connect only**
  (free, India-resident storage, no cross-border transfer). No paid aggregator
  (Rook/Terra/…) without a new decision.
- **Data model (Section 6 extension).** `wearable_connections`,
  `wearable_metrics_daily`, `wearable_workouts` (optional `visit_id`), optional
  short-lived raw samples with retention; `grant_type` gains `'wearable'`; visits
  gain optional structured `advice`.
- **Clinical-safety.** Raw trends only — NO auto-diagnosis, scoring, or alerting
  (consistent with Section 8). Regulated signals (ECG/AFib, SpO2, BP, CGM) shown
  informational, non-diagnostic.
- **Non-functional.** Continuous physiological data is sensitive under the DPDP
  Act; encryption + retention limits + purpose-limited consent apply.
