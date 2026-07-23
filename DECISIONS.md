# Ayulekha — Resolved Decisions (v1)

> Authoritative answers to the six open questions raised at kickoff. These are **decided** — the
> coding agent should implement them, not re-litigate. Where this file and `CLAUDE.md` differ, this
> file wins until the two are reconciled. Date: 2026-06-25. Owner: Mohan.

## D1 — Per-doctor PIN on top of the clinic login (ADOPTED)

The clinic still has one login credential (registration number + phone/OTP), but **each doctor under
the clinic has a personal numeric PIN**.

- Solo clinic: PIN is set at first login; the single session is doctor + admin as before.
- Multi-doctor clinic: the "Who are you?" picker still appears, but selecting a doctor (or "Clinic
  Admin / View All") now **requires entering that identity's PIN** before the session is scoped.
- Admin role has its own PIN, set by whoever registers the clinic.
- PINs are hashed (never stored plaintext), rate-limited, and resettable by the clinic admin.
- This makes AC-9 (clinical accountability) and doctor-scoping actually enforceable: a session can
  only act as an identity whose PIN was entered.

## D2 — DB-level scope enforcement via a signed scope token (ADOPTED)

RLS cannot tell a doctor-scoped from an admin-scoped request when both share one clinic auth user.
Fix: after clinic login **and** a successful PIN entry (D1), a Supabase **Edge Function mints a
short-lived scoped JWT** carrying custom claims:
*(Minting mechanics superseded by D9 — the claims and rules below still apply verbatim.)*

```
{ clinic_id, active_role: "doctor" | "admin", active_doctor_id: <uuid|null> }
```

- RLS policies read these claims (`auth.jwt() ->> 'active_doctor_id'`, `... ->> 'active_role'`,
  `... ->> 'clinic_id'`) — app state is never trusted for access decisions.
- Switching identity (e.g. doctor A → doctor B, or doctor → admin) requires re-entering the target
  PIN, which mints a new token. No client-side role flipping.
- Token TTL is short (e.g. 30–60 min) with silent refresh while the PIN-backed session is active.
- Section 12 guarantees (a/b/c) are then enforced in SQL, not just Dart.

## D3 — Phone-first account, ABHA-linkable, gate behind a flag (ADOPTED)

- MVP patient signup is **phone + OTP**; ABHA linking is offered inline and strongly encouraged but
  **not hard-blocking** while ABDM auth is mocked.
- A single config flag `REQUIRE_ABHA` (default `false` for pilot) flips to `true` to enforce ID-1
  once real ABDM integration lands (Phase 11).
- `patients.abha_id` becomes nullable for now; a patient record is keyed on phone until ABHA links.
- Preserves ID-1's intent without blocking the pilot or our own test users.

## D4 — Remote-flow (Flow B) grants default to `standing` (ADOPTED)

- Flow A (in-person QR) → `standing` (unchanged).
- Flow B (remote, patient-approved) → also **`standing`** by default, so a patient who approves a
  doctor once isn't re-prompted every visit.
- `one_time` remains in the enum for a future "share once / time-bound" option but is **not created
  by any MVP flow**. Document it as reserved.

## D5 — Structured prescription frequency (ADOPTED)

Replace the loose `frequency` / `duration` text with structured fields so medication reminders
(NT-2 / PT-11) can be scheduled deterministically:

```
prescriptions
  id, visit_id, drug_name, dosage,
  schedule jsonb           -- e.g. {"morning": true, "afternoon": false, "night": true}
  relation_to_food text    -- enum: before | after | with | none
  duration_days int,
  instructions text        -- optional free text, NOT used for scheduling
```

- Reminder times map from the `schedule` booleans to clinic/patient-configurable clock times
  (default morning 08:00, afternoon 14:00, night 21:00).
- Voice/template entry must populate these structured fields, shown for doctor review before save.

## D6 — External-dependency owners flagged, defaults proposed (ADOPTED, pending Mohan's pick)

These are **flagged, not silently chosen** — agent must confirm before wiring real services:

- **Voice prescription STT:** default recommendation = on-device speech-to-text (Flutter
  `speech_to_text` plugin) for MVP — zero per-call cost, no PHI leaves device. Cloud STT (better
  Indian drug-name accuracy) is a later upgrade. Decision owner: Mohan.
- **AI tap-to-source attribution:** Claude returns `sentence_sources`, but the Edge Function must
  **validate every returned `visit_id` / `test_order_id` against the actual input set** and drop any
  hallucinated reference before display. Non-negotiable safety step; no extra vendor.

## D7 — AI summary provider: Groq (interim), Claude-ready (ADOPTED 2026-07-04)

CLAUDE.md Sections 3/8 name the Claude API. Founder approved launching on **Groq**
(`llama-3.3-70b-versatile`, JSON mode) because its free tier costs nothing and its API terms do
not train on submitted data. The Edge Function is provider-agnostic: setting `ANTHROPIC_API_KEY`
switches to Claude with **no code change** (it wins over `GROQ_API_KEY` if both are set).
Everything else in Section 8 is unchanged: server-side only, structured-fields-only input, exact
system prompt, source-id validation, mandatory verify label. Cross-border data flow to Groq (US)
is flagged for DPDP review (audit register M4) — revisit before real launch.

## D8 — "Hospital" entry + self-registration (ADOPTED 2026-07-04, founder instruction)

- The entry button reads **"Hospital"**, not "Doctor" (same clinic structure behind it).
- Hospitals **self-register in-app**: hospital name + registration/license number + mobile +
  admin PIN. Solo doctors follow the SAME path — register the hospital, then add their own
  doctor profile (name, council reg number, council name, specialty, optional HPR) under it.
- Registration creates the clinic with an empty roster; doctors are added from the admin-scoped
  "Manage doctors" screen. Supersedes any assumption that clinics are pre-provisioned.

## D9 — Scope claims via GoTrue + access-token hook, not self-minted JWTs (ADOPTED, supersedes D2 mechanics)

D2's *intent* stands (short-lived scoped claims read by RLS; PIN required to switch identity),
but the *mechanism* changed in Phase 4.5: instead of the Edge Function minting its own HS256
JWT, each clinic gets a real service-provisioned GoTrue user (password encrypted in Vault,
service-role-readable only). The `mint-scope-token` function verifies the PIN (D1), writes the
chosen scope to `scope_sessions`, and a **custom access-token hook** injects
`clinic_id / active_role / active_doctor_id` into every token GoTrue issues. The client just
refreshes its session to pick up new claims. Strictly stronger than D2: asymmetric signing,
standard refresh/revocation, no signing secret in function code.

## D10 — Interim clinic-login hardening until Phase 11 OTP (ADOPTED 2026-07-04, audit H1/H2/M3)

Real SMS OTP needs a paid provider (founder sign-off pending — Phase 11). Until then:
- Clinic login requires the **registered phone number** as a second factor alongside the
  registration number (normalized to last-10-digits comparison).
- Per-IP rolling rate limits on register/login/scope (`carebridge_rate_ok`, 20/10 min).
- Self-registered hospitals carry `clinics.verified = false` and show a "pending verification"
  banner until the founder confirms the registration number (founder-settable flag).
These are explicitly interim; Phase 11 replaces the phone factor with real OTP.

## D11 — OTP via Firebase Phone Auth; ABHA optional-capture until ABDM keys (OTP PART SUPERSEDED BY D12)

Founder decisions for Phase 11:

- **OTP provider = Firebase Phone Auth** (Indian numbers/operators; ~USD 0.01/SMS on the Blaze
  plan; console "test phone numbers" work free for development). The client verifies the SMS code
  with Firebase and sends the resulting **ID token** to `mint-scope-token`, which verifies it
  server-side (Google JWKS, issuer/audience pinned to the Firebase project) and trusts ONLY the
  token's `phone_number` claim. Applies to patient sign-in AND hospital login (fully closes audit
  H1 once enforced). Flag-gated: no Firebase config in the client = demo login remains, clearly
  labelled; `REQUIRE_OTP=true` in Supabase secrets makes verified OTP mandatory server-side.
- **ABHA**: captured as an OPTIONAL 14-digit profile field (unverified), with a link to the
  official ABDM self-registration page for patients who have none. Verifying an existing ABHA
  requires ABDM sandbox credentials (M1 APIs: `/v1/auth/init` + OTP confirm) — deferred until the
  founder's sandbox application is approved. `REQUIRE_ABHA` (D3) flips ABHA to mandatory when the
  platform is ready. Supersedes nothing; this sequences D3's intent.

## D12 — OTP is Supabase-hosted; MSG91 sends the SMS (ADOPTED 2026-07-06, supersedes D11's provider)

Founder revisited D11 the same day after seeing Firebase SMS pricing (~USD 0.01/SMS): too costly
for Indian volumes. New shape, same trust guarantees:

- **Codes are OURS**: `mint-scope-token` generates a 6-digit code, stores a SHA-256 hash in the
  service-only `auth_otps` table (5-minute expiry, 5 attempts, single use), and verifies it at
  login. Rate-limited per IP AND per phone (SMS costs money).
- **Only the SMS send is provider-specific** (MSG91 flow API, ~INR 0.15–0.25/SMS after DLT
  registration) — swappable via `MSG91_AUTH_KEY`/`MSG91_TEMPLATE_ID` secrets, exactly like the
  Groq/Claude AI-provider pattern (D7). No Firebase client SDK in the app at all.
- **Degrades cleanly**: while the MSG91 secrets are absent, `send_otp` answers
  `otp_not_configured` and the login screens fall back to the demo path; `REQUIRE_OTP=true`
  refuses that fallback once SMS works. Applies to patient sign-in AND hospital login (H1).
- Bonus over Firebase: no authorized-domain restriction — OTP works from LAN/IP test hosts.
- Founder TODO: MSG91 account + KYC + DLT entity/template registration (one-time, ~days).

## D13 — Per-doctor mobile login (ADOPTED 2026-07-07, founder enhancement)

Amends Section 2.2's "one login credential per clinic". Problem: with a single
hospital login (registered mobile → OTP → "Who are you?" → PIN), a multi-doctor
hospital's admin had to hand the hospital login to every doctor. Fix: a doctor
gets their OWN mobile on the roster (`doctors.phone`, migration 0023, unique on
normalized last-10). On the hospital sign-in screen the entered number resolves
BOTH ways:

- matches a clinic phone → hospital/admin login (unchanged, tried FIRST so a solo
  doctor sharing the hospital number is unaffected);
- else matches a doctor phone → authenticate as that doctor's clinic GoTrue user
  and return `preselected_doctor_id/name`; the client skips the picker and goes
  straight to that doctor's PIN → their own doctor-scoped workspace.

Nothing about the scope/RLS/PIN model changes (D1/D2/D9): the doctor still signs
in as the clinic user and is scoped by their PIN. This only adds a second
resolution path in `mint-scope-token`'s `login` action. The entry button is
relabelled "Hospital / Doctor". Doctor phone is OPTIONAL at roster-add; without
it that doctor uses the shared hospital login + picker as before. When OTP is
live (D12), the SMS goes to whichever number was entered (the doctor's own for a
doctor login).

## D14 — Wearables & vitals epic (PLANNED 2026-07-23, post-MVP Phases 12+)

Fold fitness-band / smartwatch vitals into Ayulekha. **Planned, not built** —
full design in `docs/EPIC_wearables.md`, PRD summary `PROJECT_BRIEF.md` §13,
hard rules `CLAUDE.md`/`AGENTS.md` §15. Two independent goals: (1) a standalone,
always-free **Strava-style patient fitness tracker** (steps, calories, workouts,
sleep, HR, streaks) usable with no doctor; (2) an opt-in, **paid** doctor
trend + adherence view that ties wearable data to a visit's advice to answer
"did the patient follow it / did they improve".

Key calls recorded:
- **On-device capture only** for MVP — Apple HealthKit + Android Health Connect
  (free, India-resident storage). No paid aggregator (Rook/Terra/Spike/Thryve)
  without a new decision — it reintroduces cost and DPDP cross-border exposure.
  Aggregator kept as a deferred, unscheduled paid fallback for band/web coverage.
- **New, separate, revocable `wearable` consent scope** (add to `grant_type`),
  **patient-initiated** ("Share vitals" toggle per doctor), never automatic,
  logged as `what_viewed='wearable data'`, checked by its own visibility helper
  `current_scope_can_view_wearables()`. A plain clinical `standing` grant must
  NOT confer vitals access. **Clinic admin AC-8 does NOT auto-inherit** (stricter
  than clinical visit data — a deliberate departure from D-none/Section 7).
- **Structured visit-advice fields** on `visits` (e.g. `advice jsonb`) so the
  doctor view overlays actual-vs-target, not just a date marker.
- **Strictly non-diagnostic** (mirrors Section 8): raw trends only, no scores or
  alerts; regulated signals (ECG/AFib, SpO2, BP, CGM) shown informational only.
- **Paid gating** (Section 9) for the doctor view; patient view free.
- **Phasing:** P12 patient tracker + consent foundation; P13 doctor view + visit
  linkage; P14 follow-up loop + BP inputs. Each returns for approval.

---

### Net effect on the data model

- `patients.abha_id` → nullable (D3).
- `doctors` → add `pin_hash`; `clinics` → add an admin `pin_hash` (D1).
- Scope claims live in the JWT, not a table (D2).
- `prescriptions` → structured `schedule` / `relation_to_food` / `duration_days` (D5).
- `doctors` → add `phone` (nullable, unique on normalized last-10) for per-doctor login (D13).
- PLANNED (D14, Phases 12+): `grant_type` → add `'wearable'`; new `wearable_connections` / `wearable_metrics_daily` / `wearable_workouts` tables (+ optional short-lived raw samples); `visits` → optional structured `advice`. Not built yet.
