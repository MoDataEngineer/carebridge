# Wearables Integration — HealthKit / Health Connect (Phase 12)

> Built 2026-07-25. Companion to `docs/EPIC_wearables.md` (design), `DECISIONS.md`
> D14/D15, `CLAUDE.md`/`AGENTS.md` §15. This is the developer reference for the
> on-device sync: what we read, how it maps across platforms, the safety
> boundary, and the native setup that a device build needs.

## 1. Design stance — raw types only, never derived scores

We ingest **only the raw, standardized data types** HealthKit / Health Connect
expose, and we surface them as-is. We deliberately **do NOT compute any composite
/ derived "score"** — no recovery %, strain, readiness, sleep-performance %,
"WHOOP Age", or stress index.

This is not a gap; it is the safety boundary. Those composites are proprietary
**interpretations**, and neither platform has a data type for them (see the WHOOP
research note in the repo). Deriving one ourselves would cross the non-diagnostic
line the epic draws (§6, mirroring the AI-summary rule): the app **displays**;
the doctor **interprets**. Device-reported scores (if a vendor writes one) would
be shown verbatim, attributed to the device — but we generate none.

Regulated signals (SpO₂, blood pressure, ECG/AFib events, glucose) are
**display-only** and always carry "informational, from your device — not a
diagnostic measurement."

## 2. Metric map (what we read → platform types)

Implemented in [`health_source_native.dart`](../app/lib/features/vitals/health/health_source_native.dart).
`HK` = Apple HealthKit, `HC` = Android Health Connect.

| Our metric | HK type | HC type | Notes |
|---|---|---|---|
| Steps | `STEPS` (via `getTotalStepsInInterval`) | `STEPS` | Dedicated helper is more accurate than summing samples. |
| Active energy | `ACTIVE_ENERGY_BURNED` | `ActiveCaloriesBurned` | kcal. |
| Active minutes | `EXERCISE_TIME` | (exercise) | Apple "exercise minutes"; falls back to workout durations. |
| Resting HR | `RESTING_HEART_RATE` | `RestingHeartRate` | bpm. |
| **HRV** | `HEART_RATE_VARIABILITY_SDNN` | `HeartRateVariabilityRmssd` | **Platform mismatch** — iOS exposes only SDNN, Android RMSSD. We label which (`hrvIsRmssd`) so the two are never silently compared. |
| Respiratory rate | `RESPIRATORY_RATE` | `RespiratoryRate` | breaths/min. |
| SpO₂ | `BLOOD_OXYGEN` | `OxygenSaturation` | Regulated → display-only. Normalised to a %. |
| Skin temperature | `SKIN_TEMPERATURE` | `SkinTemperature` | Δ from baseline °C. |
| Distance | `DISTANCE_WALKING_RUNNING` | `DISTANCE_DELTA` | Metres → km. |
| Floors | `FLIGHTS_CLIMBED` | `FloorsClimbed` | |
| Sleep | `SLEEP_ASLEEP` | `SLEEP_SESSION` | Summed over last night (prev 18:00 → today 12:00). |
| Workouts | `WORKOUT` | `ExerciseSession` | `WorkoutHealthValue` → type/duration/distance/energy. |
| Blood pressure | `BLOOD_PRESSURE_SYSTOLIC/DIASTOLIC` | `BloodPressure` | Regulated → display-only. |

**Not available in `health` 13.x:** VO₂max has no enum in this plugin version —
dropped from the read set (would return nothing). ECG waveforms and irregular-
rhythm events are not surfaced (regulated; the platforms don't expose a portable
type we'd display raw).

Requesting a type the current OS/device doesn't expose throws, so the read set is
filtered by `isDataTypeAvailable()` before every query.

## 3. Vendor coverage (set onboarding expectations)

On-device hubs capture whatever the user's band/app writes into them — coverage
is **not uniform** (see the WHOOP research doc for the full matrix). Highlights
that shape our India-first onboarding:

- **Apple Watch → HealthKit**: full, iOS-only.
- **Samsung, Noise, boAt, Fire-Boltt, Amazfit (Zepp) → Health Connect**: via each
  vendor's own app; Android-mostly, sometimes needs manual linking.
- **Fitbit**: writes to Health Connect (Android) but **never natively to Apple
  HealthKit** — iOS Fitbit users need a bridge app.
- **Garmin → Health Connect**: one-way since Jul 2025; withholds Body Battery /
  training load / HRV status (we don't need those).
- **Ultrahuman Ring**: strong HealthKit citizen (India brand).

Because Apple Watch penetration is lower in India, **Health Connect coverage
matters most for our market.** The accepted MVP gap: users who never install
their vendor's companion app, or want web-only sync.

## 4. Consent — two independent layers (epic §5)

1. **OS layer** — the patient grants Ayulekha HealthKit / Health Connect *read*
   permission on their phone (`requestPermissions()` in the health source). No
   permission → no connection recorded.
2. **App layer (Phase 13)** — separately, the patient grants a *specific doctor*
   the revocable `wearable` scope. **Neither implies the other.** Connecting a
   tracker never shares anything; a clinical grant never reveals vitals; clinic
   admins never auto-inherit vitals.

We only ever request **READ** access — never write to the user's hub.

## 5. Data flow & storage

Phone reads the hub → shows the patient's own view → **best-effort** upserts daily
aggregates into `wearable_metrics_daily` (India-resident Supabase, RLS-scoped to
the patient). Capture is on-device and storage is India-resident, so there is **no
cross-border transfer** (DPDP win, epic §5). A sync failure never blocks the view.

- `DemoVitalsRepository` — web / desktop / tests: fabricated data so the tracker
  is always demoable.
- `LiveVitalsRepository` — real iOS/Android device: reads via `HealthSource`,
  persists aggregates. Selected by `vitalsRepositoryProvider` when
  `HealthSource.platformSupported` is true.
- `package:health` is kept out of the web build entirely via conditional import
  (`health_source_stub.dart` on web, `_native.dart` on device) — same pattern as
  the PDF viewer.

## 6. Native setup (required for a device build)

The Dart integration is complete; a **device build** needs the platform config
below. iOS can only be built on a Mac.

**Android** (done in-repo):
- `AndroidManifest.xml`: `android.permission.health.READ_*` for each type, the
  `com.google.android.apps.healthdata` package query, and the
  `ACTION_SHOW_PERMISSIONS_RATIONALE` + `VIEW_PERMISSION_USAGE` intents.
- `MainActivity` extends `FlutterFragmentActivity` (Health Connect needs it).
- `minSdk` raised to 26.
- On a device: **Health Connect** must be installed/updated (Android 14+ bundles
  it; older needs the Play Store app).

**iOS** (in-repo, plus one Xcode step):
- `Info.plist`: `NSHealthShareUsageDescription` + `NSHealthUpdateUsageDescription`.
- `Runner.entitlements`: HealthKit entitlement created — **but inert until** the
  **HealthKit capability** is enabled in Xcode (Runner target → Signing &
  Capabilities → + Capability → HealthKit). That wires
  `CODE_SIGN_ENTITLEMENTS`, links `HealthKit.framework`, and updates the
  provisioning profile. A physical device is required (HealthKit is unavailable
  in the simulator).

**Windows dev note:** building the Android app with plugins needs Developer Mode
(symlink support) enabled — `start ms-settings:developers`.

## 7. Deferred / not built

- **WHOOP (and other) first-party OAuth APIs** — the only path to true vendor
  composite scores. Out of scope: reintroduces per-vendor OAuth, cost, and (for
  US clouds) cross-border transfer. Would need a new decision.
- **A paid aggregator** (Rook/Terra/Spike/Thryve) for band/web coverage — same,
  deferred (cost + DPDP cross-border), per D14.
- **Phase 13**: the doctor trend/adherence view + `wearable` sharing UI + paid
  gating. **Phase 14**: follow-up-loop overlay + Bluetooth/manual BP entry.
