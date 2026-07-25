# Epic: Wearables & Vitals Tracking

> **Status: Phase 12 BUILT (2026-07-25); Phases 13–14 planned.** This is the
> authoritative design record for a post-MVP module. Each phase returns for its
> own approval before any code is written. Companion records: `DECISIONS.md`
> D14, `PROJECT_BRIEF.md` §13, `CLAUDE.md`/`AGENTS.md` §15.
>
> **P12 build note.** Data model (`0034`/`0035`), the `current_scope_can_view_wearables()`
> helper, patient RLS + the `wearable` share/revoke RPCs, and the patient's
> standalone daily view + connect flow (`app/lib/features/vitals/`, Vitals nav
> tab) are in the repo. The daily view ships against a **demo data source**
> (`DemoVitalsRepository`) so it is usable/verifiable now; the **real on-device
> sync** — the `health` plugin reading HealthKit/Health Connect into
> `SupabaseVitalsRepository` — is the remaining P12 step and needs (a) a new
> dependency decision (§12) and (b) a physical-device build to verify. Migrations
> `0034`/`0035` are written but **not yet deployed** (`supabase db push`).

## Two independent goals

1. **Patient value — standalone, always free.** Ayulekha becomes a real daily
   fitness tracker in its own right: a Strava-style live/daily view of steps,
   calories, active minutes, workouts, sleep, heart rate, streaks and personal
   bests. **Useful to the patient even if they never share it with any doctor** —
   an engagement/retention driver on its own.
2. **Clinical value — opt-in, consented.** When the patient chooses to share,
   the visit → follow-up loop becomes objective: a doctor writes advice at a
   visit ("brisk walk 30 min ×5/week, cut salt") and at follow-up sees whether
   the patient actually did it (active minutes, workouts) and whether it helped
   (resting-HR, home-BP trend).

The patient tracker stands on its own; the doctor loop is a consented layer on
top, never a precondition.

---

## 1. Vision & value — the "did they follow advice / did they improve" loop

Today a follow-up is subjective ("how have you been?"). Wearables make it
measurable. The chain is: **visit advice → measurable behaviour → measurable
outcome**, anchored to the visit and its `follow_up_date`.

| Visit advice (example) | Behaviour metric (did they do it?) | Outcome metric (did it help?) |
|---|---|---|
| Brisk walk 30 min ×5/week | active minutes, walking workouts/week, steps | resting HR trend, weight |
| Reduce salt / manage hypertension | — | home BP (cuff) trend, resting HR |
| Improve sleep hygiene | bedtime consistency | sleep duration, REM/deep, awakenings |
| Post-cardiac-event activity ramp | active minutes, HR zones during workouts | resting HR, HRV trend |
| Diabetes lifestyle plan | active minutes, workouts | CGM time-in-range (display-only) |

Each metric maps to the existing `visits` row (advice) and the `follow_up_date`
window, so the doctor sees the trend **from the advice date onward**, not a
context-free number.

## 2. Roles & views

- **Patient (free, standalone).** A full Strava-style daily/live fitness view:
  today's rings (steps, calories, active minutes), a workouts feed with
  per-session stats, sleep, heart rate, week/month trends, streaks, personal
  bests, and goal setting. Works entirely on its own — no doctor, no sharing
  required.
- **Doctor (paid, only if the patient shares).** A per-patient trend + adherence
  view, scoped to **one** patient and **linked to a prior visit's advice**
  (actual-vs-target overlay). Sits beside the existing Summary / History / Tests
  tabs in the doctor workspace.
- **Diagnostic partner.** Out of scope — never sees wearable data.
- **Clinic admin (AC-8).** ⚠️ **Does NOT auto-inherit** wearable visibility. This
  is deliberately stricter than clinical visit data (where AC-8 lets an admin
  see a patient any clinic doctor has a grant for). Wearable sharing is its own
  explicit patient → specific-doctor grant.

## 3. Integration strategy

**MVP = Apple HealthKit (iOS) + Android Health Connect (Android) only.** Both are
free, store data locally/encrypted on the device, and expose HR, HRV, sleep
stages, SpO2, workouts, BP, etc. The Flutter client reads from the hub and pushes
**aggregates** into our own India-resident Supabase with the patient's consent.

**Why on-device hubs (not per-vendor SDKs, not a paid aggregator):**
- **Free**, no per-user fees, no partner-approval friction (Garmin's Health API
  needs business approval + possible license fees; Fitbit's legacy API is
  deprecated Sept 2026; Whoop is simpler but still its own OAuth).
- **Privacy win:** capture stays on the patient's phone and flows only into our
  own India-resident backend — **no US cross-border transfer** (the biggest DPDP
  risk of an aggregator; see §5).
- **Google Fit APIs are deprecated in 2026** — Health Connect is the successor
  and the only viable Android path.

**Honest coverage note.** On-device hubs capture whatever the user's band/app
writes into them. In practice that is broad: Apple Watch → HealthKit; Samsung and
the dominant Indian budget bands (Noise, boAt, Fire-Boltt, Amazfit via Zepp) →
Health Connect through their own apps; and Fitbit/Garmin/Whoop can also sync into
Health Connect/HealthKit via their apps. The accepted MVP gap: users who never
install the vendor app, or want web-only sync.

**Deferred, paid fallback (NOT now):** a unified aggregator — Rook
(~$0.50/user/mo), Terra (~$399–499/mo base + credits), Spike, or Thryve — could
later fill band/web coverage gaps. It would reintroduce cost **and** US data
residency (cross-border, §5), so it requires a **new decision** before adoption.

**Bluetooth BP cuff:** captured through the hub if the cuff's app writes to it,
otherwise **manual patient entry** as a fallback.

## 4. Data model

Modeled on the existing schema conventions (security-definer RPCs, RLS, partial
indexes). **Created later, in Phase 12+ — not now.**

- **`grant_type` enum gains `'wearable'`** (today `standing | one_time |
  order_scoped`). Reuse `granted_to_type = 'doctor'` and the existing
  `status` / `expires_at` / `revoked_at` columns on `access_grants` — no new
  grant columns needed.
- **`wearable_connections`** — `patient_id` FK, `provider`
  (`apple_health | health_connect | manual`), granted scopes, `status`,
  `connected_at`, `revoked_at`. One row per connected source.
- **`wearable_metrics_daily`** — `patient_id`, `metric_type`, `date`,
  `value` / `min` / `max` / `avg`, `source`. **The long-term store is daily
  aggregates** (keeps continuous streams small).
- **`wearable_workouts`** — `patient_id`, `type`, `start`, `duration`,
  `distance`, `avg_hr` / `max_hr`, `calories`, `hr_zones`, optional `visit_id`
  FK (`on delete set null`).
- **`wearable_samples_raw` (optional, short-lived)** — intraday samples with a
  **30–90 day retention** then downsample to daily. Retention/partitioning is
  greenfield (no existing precedent in the schema) — call it out explicitly when
  built. Composite/partial indexes `(patient_id, recorded_at)`.
- **`visits` advice fields (Phase 13)** — an optional structured `advice`
  column (e.g. `jsonb` like `{activity_target, diet_note, ...}`) so the doctor
  view can overlay **actual vs target**, not just a date marker.

**Volume & retention.** Persist **aggregates**, not raw forever. Sync is
client → Supabase (the phone reads the hub and pushes), so there is no
server-side third-party fetch. Realtime (if used for a live view) rides the
existing `supabase_realtime` publication pattern, but every streamed row runs its
RLS predicate — keep it index-backed.

## 5. Consent & privacy (CRITICAL)

**A new, separate, revocable grant scope: `wearable`.** Distinct from the
clinical `standing` / `one_time` / `order_scoped` scopes.

- **Patient-initiated.** In the patient "Doctors with access" screen the patient
  turns ON "Share vitals" for a specific doctor (typically one who already holds
  a clinical grant). This creates a `wearable` `access_grants` row. **Never
  automatic.**
- **Two consent layers:** (a) OS-level — the patient grants Ayulekha
  HealthKit/Health Connect read permission on their phone; (b) app-level — the
  patient grants a **specific doctor** the `wearable` scope. Neither implies the
  other.
- **Separate visibility check.** A dedicated helper
  `current_scope_can_view_wearables(patient)` — a normal clinical `standing`
  grant must **not** confer wearable access (the existing patient-visibility
  helper ignores grant `type`, so wearable tables must be gated by the new
  helper, not the generic one).
- **Admin AC-8 does not apply** to wearable data.
- **Audited.** Every doctor read is logged in `access_logs` with
  `what_viewed = 'wearable data'`, visible to the patient under "Who viewed my
  records."
- **Revocable** one-tap, same as clinical grants (filtered to `type='wearable'`).

**DPDP (India Digital Personal Data Protection Act).** Continuous physiological
data is sensitive personal data. Because MVP capture is **on-device** and storage
is our **India-resident** Supabase, there is **no cross-border transfer** — the
main DPDP exposure of a US aggregator is avoided. Still required: explicit,
purpose-limited consent; retention limits; encryption at rest and in transit. If
a paid aggregator is ever adopted (§3), it becomes a cross-border transfer under
DPDP Rule 15 / Section 16 and needs its own consent line and assessment.

## 6. Clinical-safety boundary

**Surface raw trends only.** Consistent with the AI-summary non-diagnostic rule
(PROJECT_BRIEF §8), this module must **never**:
- auto-diagnose, compute a risk score, or generate a health "grade";
- raise abnormality **alerts** or thresholds that constitute medical advice.

Device-derived scores (e.g. Whoop recovery, "readiness") are shown **exactly as
the device reported them**, never generated by us. ECG/AFib, SpO2, BP, and
CGM/glucose are shown as **"informational, from the patient's device — not a
diagnostic measurement."** Generating alerts or interpretations over these would
risk crossing into **regulated medical-device** territory (and a duty to act) —
explicitly out of scope. The doctor interprets; the app only displays.

## 7. Subscription placement (PROJECT_BRIEF §9)

- **Free:** the patient's own vitals/daily view **and** connecting a tracker
  (HealthKit/Health Connect). Patients are never charged.
- **Paid (clinic Pro):** the **doctor's** per-patient trend + adherence view, the
  advice-vs-actual overlay, and wearable data feeding the follow-up tracker.
- With on-device capture there is **no external per-user cost** — the paid line
  is a pure feature gate, following the existing `current_clinic_is_paid()` /
  `scope.paid` / `UpgradeScreen` pattern.

## 8. Phasing (post-MVP, Phases 12+)

Each phase ships with trust tests and returns for approval.

- **Phase 12 — Patient tracker + consent foundation.**
  `wearable` grant scope + data-model tables + patient connect
  (HealthKit/Health Connect) + the standalone patient daily/live fitness view.
  *Trust tests:* OS-permission gating; a `wearable` grant is never created
  without the patient toggle; revoke closes access; wearable tables are **not**
  visible via a plain clinical grant.
- **Phase 13 — Doctor view + visit linkage.**
  Structured visit-advice fields; the paid, per-patient doctor trend + adherence
  view; advice-vs-target overlay.
  *Trust tests:* doctor sees wearables **only** with an active `wearable` grant;
  **admin AC-8 does NOT see wearables**; paid gating enforced server-side; access
  logged as `wearable data`.
- **Phase 14 — Follow-up loop + inputs.**
  Wire wearable adherence into the follow-up tracker + reminders; Bluetooth /
  manual BP entry.
  *Trust tests:* reminders carry no PHI; overlay respects grant + revoke.
- **Deferred (unscheduled):** optional paid aggregator for band/web coverage —
  requires a new decision (cost + cross-border).

## Appendix A — Metrics to support (where the device provides them)

Steps · distance · floors climbed · active / Zone minutes · calories (active +
total) · resting HR · continuous HR · **HRV** · HR zones · **SpO2** · respiratory
rate · skin/body temperature · **sleep** (total, REM/deep/light, awakenings,
sleep score) · device stress / readiness / recovery scores (shown as-is) ·
**VO2max / cardio fitness** · **ECG / AFib** · **blood pressure** · **blood
glucose / CGM** · body composition (weight, BMI, body-fat from smart scales) ·
menstrual / cycle tracking · hydration · mindfulness minutes.

*(Bold + regulated: ECG/AFib, SpO2, BP, CGM — display-only, non-diagnostic, §6.)*

## Appendix B — Workout types to support

Walking · running · cycling · swimming · strength training · HIIT · yoga ·
pilates · elliptical · rowing · hiking · dance · treadmill · stair climbing ·
cross-training · and India-popular sports: cricket, football, badminton, tennis,
kabaddi. Per workout: duration, distance, avg/max HR, calories, HR-zones, pace.
These feed the "did they do the prescribed regimen?" adherence view.
