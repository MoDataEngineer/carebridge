# Phase 4.5 (pre-Phase 5) — Retire legacy HS256 secret, move to asymmetric JWT signing

> **Status:** ✅ COMPLETE (2026-06-27). All 8 steps done; live asymmetric token
> path proven; legacy HS256 secret revoked → leaked `service_role` key is inert.
> Phase 5 (access-grant / consent core) is now unblocked.
>
> **Owner:** Mohan · **Created:** 2026-06-25 · **Completed:** 2026-06-27 · **Blocked:** Phase 5 (now cleared)

## Why this exists

The D2 scoped-token system currently signs its own JWTs **HS256 with the legacy
`SUPABASE_JWT_SECRET`**. That same legacy secret also verifies the project's
`anon` / `service_role` keys, so it **cannot be rotated/revoked** without breaking
both those keys *and* the HS256 tokens the `mint-scope-token` Edge Function issues.

A copy of `app/.env` containing the `service_role` key was briefly committed to the
(private) GitHub repo and has since been scrubbed from history (force-push, hashes
rewritten). Scrub + private repo **contains** the practical exposure, but the only
way to make the leaked key definitively worthless is to retire the legacy secret —
which requires first moving the scoped-token mechanism off it. That is this task.

## Current state (verified)

- RLS scope enforcement is real and tested at the DB level — but only with
  **simulated** claims (`set_config`), not live tokens. (Phase 2 trust tests b/c.)
- `auth.jwt()` reads `request.jwt.claims`, populated by PostgREST/GoTrue **only
  after** verifying the token signature — clients cannot forge claims via the API.
- SECURITY DEFINER functions pin `search_path` (`public`, or `public, extensions`);
  `anon`/`authenticated` have no `CREATE` on `public`.
- The end-to-end **mint → verify → `auth.jwt()` → RLS** path has **never** been
  exercised against this project's keys.

## The constraint that forces a redesign

With **asymmetric** JWT signing keys, Supabase holds the private key and signs the
tokens GoTrue issues. You **cannot** self-mint a project-signed token anymore, so
the HS256 `signToken()` path in `supabase/functions/mint-scope-token/index.ts` must
be **replaced**, not merely re-keyed.

---

## Option A — Custom Access Token Auth Hook  ✅ CHOSEN

**Why chosen:** preserves **Decision D2** (scope claims travel inside the verified
JWT) and leaves the RLS helpers (`current_clinic_id` / `current_active_role` /
`current_active_doctor_id`) and all 0003 policy bodies **completely unchanged**.
It is also Supabase's recommended pattern for custom claims under asymmetric keys.

**How it works:**
- A small server-side table holds the verified scope chosen after PIN:
  ```
  scope_sessions
    auth_uid       uuid primary key,     -- the clinic auth user (auth.uid())
    clinic_id      uuid not null,
    active_role    text not null,        -- 'doctor' | 'admin'
    active_doctor_id uuid,               -- required when active_role = 'doctor'
    updated_at     timestamptz not null default now()
  ```
- A **Custom Access Token Hook** (Postgres function registered with GoTrue) reads
  the caller's `scope_sessions` row and injects `clinic_id` / `active_role` /
  `active_doctor_id` into every access token GoTrue issues. Supabase signs it with
  the **asymmetric** key. RLS reads them via `auth.jwt()` exactly as today.
- **Scope selection / switching** = write/update the `scope_sessions` row (after a
  successful `carebridge_verify_pin`), then force a session refresh so the next
  token carries the new claims. No client-side role flipping; switching identity
  still goes through PIN (D1).

**Net effect:** the Edge Function's `scope` action stops signing a token and
instead updates `scope_sessions`; everything downstream of `auth.jwt()` is untouched.

## Option B — Scope-session table read directly by RLS  (FALLBACK)

If the auth-hook path is unavailable or undesirable: keep the same `scope_sessions`
table, but **drop custom JWT claims entirely**. Rewrite the three RLS helper
functions to read the active scope from `scope_sessions` joined on `auth.uid()`
instead of from `auth.jwt()`. The normal asymmetric Supabase session token is used
as-is; nothing is self-signed.

**Trade-offs vs A:**
- ➖ Diverges from D2 (scope no longer "in the verified JWT" — it's a server-side
  lookup keyed on the verified `auth.uid()`).
- ➖ One extra (cacheable, `STABLE`) table lookup per RLS evaluation.
- ➕ No token-refresh choreography on scope switch — just a row update.
- ➕ Fully decoupled from signing-key mechanics.

Keep B documented but prefer A.

---

## Decisions made during execution (2026-06-27)

- **Clinic identity:** each clinic is now a real **GoTrue auth user**
  (service-provisioned email `clinic.<reg>@carebridge.internal` + password),
  linked via `clinics.auth_user_id`. Required because the hook + `scope_sessions`
  key on `auth.uid()`, and only GoTrue-issued tokens trigger the hook. Real
  phone-OTP login stays Phase 11.
- **Clinic password storage:** stored **encrypted in Supabase Vault**, read back
  only by `service_role` via SECURITY DEFINER RPCs (`carebridge_set/get_clinic_secret`,
  migration 0008); execute revoked from anon/authenticated/public. Never returned
  to a client, never logged. Verified: round-trip + client-role execute denied.

## Migration checklist (execute in order, pre-Phase 5)

- [x] 1. Asymmetric ECC (P-256) signing key is **current**; legacy HS256 is
        **verify-only / previous** (not revoked). Verified: new tokens are `ES256`.
- [x] 2. `scope_sessions` table + RLS (migration 0006) + `clinics.auth_user_id`.
- [x] 3. Custom Access Token Hook (migration 0007) registered in the dashboard,
        injecting `clinic_id` / `active_role` / `active_doctor_id`.
- [x] 4. `mint-scope-token` reworked: `login` = Vault-backed GoTrue sign-in;
        `scope` verifies PIN then **upserts `scope_sessions`** (client refreshes).
        HS256 `signToken()` removed entirely. (Deploy at step 6.)
- [x] 5. **LIVE-token acceptance gate PASSED** (`supabase/tests/live_token_trust.ps1`):
        trust (b)/(c) + doctor↔admin switch against real ES256 tokens, claims via
        `auth.jwt()`. `LIVE_TOKEN_TRUST_OK`.
- [x] 6. Switched keys: client → **publishable** (`app/.env` `SUPABASE_ANON_KEY`);
        server → **secret** (root `.env` `SUPABASE_SERVICE_ROLE_KEY`). Fixed
        `SUPABASE_URL` (`/rest/v1/` suffix removed). Gate re-run green on new keys.
        ⚠️ Edge Function deploy (still pending) must `supabase secrets set` the new
        values. NOTE: Supabase secret keys 401 on browser-like User-Agent — the test
        harness forces a non-browser UA; Deno Edge Functions are unaffected.
- [x] 7. Revoked the legacy JWT secret (7a: disabled legacy anon/service_role API
        keys, gate stayed green → nothing depended on them; 7b: revoked the legacy
        HS256 signing secret). Leaked `service_role` key is now **inert**. ✅
- [x] 8. RLS helpers UNCHANGED (Option A). Re-verified: `rls_trust` (b)/(c)/AC-9,
        `doctor_core_rls`, `patient_rls` all PASS; `flutter test` 12/12.

## Later, optional — belt-and-suspenders hardening (not blocking)

- [ ] Tighten SECURITY DEFINER functions from `SET search_path = public` to
      `SET search_path = ''` with every identifier fully schema-qualified
      (`public.access_grants`, `public.doctors`, …). Already-safe today because
      client roles lack `CREATE` on `public`; this removes the dependency on that ACL.

## Acceptance criteria

- A live, GoTrue-issued (asymmetric-signed) token carries the scope claims and RLS
  filters rows identically to the Phase 2 simulated-claim results.
- Legacy HS256 secret disabled; `anon`/`service_role` replaced by new API keys.
- No HS256 self-minting remains in the codebase.
