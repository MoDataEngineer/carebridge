# Phase 4.5 (pre-Phase 5) — Retire legacy HS256 secret, move to asymmetric JWT signing

> **Status:** PLANNED — not started. Scheduled to run **after Phase 4, before Phase 5**.
> Phase 5 (access-grant / consent core) must not be built on an unverified token path
> that depends on a leaked-but-un-rotatable secret.
>
> **Owner:** Mohan · **Created:** 2026-06-25 · **Blocks:** Phase 5

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

## Migration checklist (execute in order, pre-Phase 5)

- [ ] 1. Dashboard: add an asymmetric (ECC) signing key; make it the **current**
        signing key. Legacy HS256 becomes **verify-only / standby** (do NOT revoke yet).
- [ ] 2. Create the `scope_sessions` table (migration) + RLS so only the owning
        `auth.uid()` row is touched; service role writes it.
- [ ] 3. Implement + register the **Custom Access Token Hook** (Option A) injecting
        `clinic_id` / `active_role` / `active_doctor_id`.
- [ ] 4. Rework `mint-scope-token`: `scope` action verifies PIN (existing RPC) then
        **upserts `scope_sessions`** and triggers a session refresh — remove HS256
        `signToken()`. Keep `login` (roster) action.
- [ ] 5. **Verify end-to-end with LIVE tokens:** re-run the Section 12 trust tests
        (b)/(c) against real GoTrue-issued asymmetric tokens (not `set_config`),
        plus a doctor→admin switch test. This is the acceptance gate.
- [ ] 6. Switch keys in app/config: client → **publishable** key (`app/.env`);
        server → **secret** key (root `.env`). Update both env files.
- [ ] 7. **Disable/revoke the legacy JWT secret.** Nothing depends on it now →
        the leaked `service_role` key is finally inert. ✅ exposure eliminated.
- [ ] 8. Confirm RLS helpers unchanged (Option A) and all Phase 2 tests still pass.

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
