# CareBridge — Claude Code Kickoff Prompt

> Paste this as your first message to Claude Code in the repo root.
> `CLAUDE.md` (the full spec) must already be present — Claude Code reads it automatically.
> This prompt tells the agent how to start, what to resolve first, and how to behave between phases.

---

You are the engineering agent for **CareBridge**, a patient-owned, multi-clinic health-record platform for India (Flutter + Supabase). The authoritative spec is in `CLAUDE.md` in this repo — read it in full before doing anything, and treat Sections 2 (identity model) and 7 (consent/access-grant logic) as the parts most likely to be implemented subtly wrong.

## Settled decisions — read `DECISIONS.md`, do not re-litigate

The six kickoff questions are **resolved in `DECISIONS.md`**. Implement them as written; where
`DECISIONS.md` and `CLAUDE.md` differ, `DECISIONS.md` wins until reconciled. In summary:

1. **D1 — Per-doctor PIN** on top of the one-credential clinic login; selecting a doctor/admin in
   the "Who are you?" picker requires that identity's PIN. PINs hashed, rate-limited, admin-resettable.
2. **D2 — Scoped JWT for RLS.** After clinic login + PIN, an Edge Function mints a short-lived token
   with `{ clinic_id, active_role, active_doctor_id }`; RLS reads these claims. No client-side role
   flipping — switching identity re-prompts for the PIN.
3. **D3 — Phone-first patient signup**, ABHA-linkable inline, gated behind `REQUIRE_ABHA` (default
   `false` for pilot). `patients.abha_id` is nullable for now.
4. **D4 — Flow B grants default to `standing`.** `one_time` stays in the enum but is reserved/unused
   in MVP.
5. **D5 — Structured prescription schedule** (`schedule` jsonb, `relation_to_food`, `duration_days`)
   replacing loose frequency/duration text, so reminders schedule deterministically.
6. **D6 — Flagged dependencies:** default to on-device STT for voice prescriptions (confirm with me
   before wiring); the AI summary Edge Function must validate every returned source id against the
   actual input set and drop hallucinated references.

Confirm you've read both `CLAUDE.md` and `DECISIONS.md`, then proceed to Phase 1 planning. Only the
D6 STT vendor choice still needs my explicit pick before you wire a real service — everything else is
go.

## How to build

- Follow the **build phasing in Section 11 exactly, one phase at a time.** Stop and summarize after each phase; wait for my review before starting the next.
- Set up the repo per Section 3.1 (monorepo: `/app` Flutter, `/supabase/migrations`, `/supabase/functions`, `/docs`). Keep `CLAUDE.md` and `AGENTS.md` identical.
- **Enforce every access-grant and session-scope rule at the database level via RLS**, not just in app code — including AC-8 (admin inherited visibility) and AC-10 (order-scoped grants).
- Write explicit tests for the three trust cases in Section 12: (a) a solo doctor never sees a "Who are you?" screen; (b) a doctor-scoped session never sees another doctor's patients; (c) an admin-scoped session sees a patient if *any* doctor in the clinic has an active grant, even if the admin never requested one.
- Never hardcode secrets — use environment variables / Supabase secrets. The Claude API is called server-side only, from the `ai-summary` Edge Function.
- The AI summary is **summarize-only** — never diagnosis or treatment, under any prompt variation. Layer 1 (safety banner) is deterministic and never AI-generated.
- `order_code` must be an unguessable random token (it grants order-scoped access when scanned).
- Stub anything that depends on credentials not yet available (ABDM/ABHA/HPR/HFR sandbox, Claude API key, FCM config) and clearly note what's needed to make it real — do not silently skip.
- Keep one Flutter codebase for all three roles and both platforms — do not fork. Use responsive layout (`LayoutBuilder`/breakpoints).
- Ask before adding any new major dependency or paid third-party service.
- If anything in the spec is contradictory or underspecified once you reach it, **stop and ask me** rather than guessing — several decisions (admin inherited visibility, clinical-accountability gating) were deliberate judgment calls.

## Start now

Read `CLAUDE.md`, then come back to me with: (1) your recommendations on the six open decisions above, and (2) the exact file/folder plan for Phase 1 (scaffold + schema + placeholder auth). Do not begin Phase 1 until I approve.
