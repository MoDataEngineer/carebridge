# CareBridge — Resolved Decisions (v1)

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

---

### Net effect on the data model

- `patients.abha_id` → nullable (D3).
- `doctors` → add `pin_hash`; `clinics` → add an admin `pin_hash` (D1).
- Scope claims live in the JWT, not a table (D2).
- `prescriptions` → structured `schedule` / `relation_to_food` / `duration_days` (D5).
