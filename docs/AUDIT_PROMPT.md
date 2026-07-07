# Ayulekha — Pre-Production Audit Prompt

> Paste the block below into Claude Code (Opus) once you're ready for a whole-system audit.
> Run Phase 0 + Phase 1 first and stop; act on High-risk findings, then let Phase 1.5 reconcile the docs.

---

You are acting as an elite principal systems architect and security auditor. This is Ayulekha — a patient-owned, multi-clinic health-record platform in Flutter (iOS/Android/Web, single codebase) on Supabase (Postgres + RLS + Storage + Edge Functions in Deno/TypeScript), built with Claude Opus 4.8. Phases 1–9 of the roadmap are complete; Phase 10 (Supabase Realtime live tracker) and Phase 11 (real ABDM/HPR/HFR integration) may still be pending or stubbed. I need your strongest reasoning to bring this to production-grade quality.

GROUND RULES — read before doing anything:
- CLAUDE.md is the authoritative product spec; DECISIONS.md holds the settled decisions. Both are canonical. You MAY update them, but ONLY to reconcile them with what was actually, intentionally built (see Phase 1.5) — via surgical, clearly-marked, approval-gated amendments. NEVER rewrite CLAUDE.md wholesale, never change its original intent, and never edit either doc to paper over a bug (if code wrongly diverged from an intended decision, fix the CODE and log it as a risk — do not rewrite the spec to match the mistake). Respect Section 13 (Simplicity First, Surgical Changes): no speculative abstractions, no gratuitous refactors.
- Security is enforced at the DATABASE level via RLS (Section 7, AC-1..AC-10) and proven by Section 12's trust tests. There is an existing passing test suite (flutter analyze clean, flutter test green, plus SQL trust harnesses against live Postgres). Nothing you propose may regress it.
- Treat Phase 10/11 items as KNOWN-PENDING, not audit failures — but flag anything already built that will need rework when they land (e.g., placeholder auth → real ABDM).
- Work sequentially and iteratively — do NOT spawn parallel sub-agents. Stop and ask for approval before ANY file modification. After each approved change, re-run flutter analyze, flutter test, and the SQL trust harness, and report results.

PHASE 0 — Establish ground truth
Read CLAUDE.md, DECISIONS.md, docs/, all supabase/migrations, RLS policies, Edge Functions, and the tests. Summarize the true architecture and current security posture before auditing.

PHASE 1 — Full security audit & hardening (threat model = multi-tenant health data)
- Object-level & multi-tenant authorization across EVERY feature built: clinic-boundary + doctor-scoping, AC-8 admin inherited-visibility, AC-9 write-gating, AC-10 order-scoped diagnostic grants (lab sees ONLY name + the one ordered test, grant auto-closes on report upload). Hunt for any path that bypasses RLS or leaks across clinics/patients.
- Confirm scope claims come only from verified auth.jwt(); every SECURITY DEFINER function pins search_path.
- Supabase Storage: lab PDFs/scan images gated by the SAME grant logic as rows (signed URLs / storage policies), never app-layer only.
- AI summary (Section 8) — NOTE: this project uses the GROQ API (server-side Edge Function), NOT the Claude/Anthropic API named in CLAUDE.md Sections 3 & 8. Flag this provider switch (it is reconciled in Phase 1.5). Verify the safety contract holds REGARDLESS of provider: Layer 1 is deterministic (never LLM-generated); Layer 2 receives ONLY structured fields (no raw notes/OCR/images); it cannot emit diagnosis/treatment under any prompt variation; every returned source id is validated against the actual input set (no hallucinated citations). The GROQ_API_KEY must live only in Supabase secrets — never client-side, never committed. Parse the Groq JSON response defensively (untrusted output).
- Subscription gating (Section 9): confirm paid-tier features are gated server-side, not just hidden in the UI.
- Notifications: medication reminders derive only from the structured D5 schedule; no PHI leaks via payloads.
- Compliance & data protection: no raw Aadhaar stored anywhere (ID-6); access logs immutable and patient-queryable, distinguishing doctor/clinic_admin/diagnostic_partner; encryption at rest + in transit; secrets split (app/.env client-safe vs root .env server-only), none bundled client-side or committable; leaked-key retirement confirmed complete. Since patient structured data is now sent to a third-party US LLM provider (Groq), flag the cross-border health-data transfer for DPDP review: confirm only minimal structured fields are sent, and note Groq's data-retention terms as an item for the compliance advisor.
- Injection/input validation on RPCs, dynamic SQL, and Edge Function inputs. Map to OWASP where genuinely applicable to a Flutter/Postgres stack.
- Deliver a risk register: High / Medium / Low, each with a concrete, minimal structural fix.

PHASE 1.5 — Spec ↔ implementation reconciliation (make the docs tell the truth)
Goal: bring CLAUDE.md and DECISIONS.md into exact agreement with what was actually built — recording real decisions, never hiding bugs.
- Produce a DRIFT REPORT: a table of EVERY place the implemented code/schema/config/config-flags diverge from CLAUDE.md or DECISIONS.md. For each row: the doc section, what the doc says, what the code actually does, and a classification — INTENTIONAL DECISION vs BUG/UNINTENDED DRIFT.
  Look especially for: the AI provider (Claude → Groq); the Phase 4.5 auth change (D2's HS256 self-minted token → asymmetric signing keys + custom access-token auth hook + scope_sessions); clinic auth (service-provisioned email+password GoTrue users); any schema fields/enums/tables added or renamed vs Section 6; REQUIRE_ABHA behaviour; new migrations; any feature deferred, added, or altered vs Sections 5/8/9; new dependencies.
- For each row classified INTENTIONAL DECISION, propose a precise, minimal doc update:
  - DECISIONS.md: APPEND a new dated decision entry (D7, D8, …) stating the change, the reason, and what it supersedes. Do NOT delete prior decisions — mark superseded ones "Superseded by Dn (date)".
  - CLAUDE.md: amend ONLY the affected section (e.g., the AI-provider references in Sections 3 & 8), preserving structure and intent, with a short "Amended (YYYY-MM-DD): …" trace note. No wholesale rewrites.
- For each row classified BUG/UNINTENDED DRIFT: do NOT change the docs to match it — add it to the Phase 1 risk register as a code fix.
- Present the full drift report and every proposed doc edit as diffs for my approval BEFORE writing anything. Apply only what I approve.

PHASE 2 — UX motion blueprint (Flutter-native, calibrated to Simplicity First)
- Analyze the widget tree and navigation state across all three role surfaces.
- Propose animation choreography using Flutter-native tools (implicit/explicit animations, Hero, PageTransitions; propose flutter_animate only if warranted — ask before adding any dependency).
- Purposeful micro-interactions only (button feedback, loading skeletons/shimmer, modal/route transitions) — not blanket motion. Every animation must respect MediaQuery.disableAnimations / accessibleNavigation (reduced-motion).
- Present as a BLUEPRINT for approval; implement nothing until I choose what's worth it.

PHASE 3 — Documentation (new files; CLAUDE.md/DECISIONS.md only via Phase 1.5 rules)
- Create docs/SYSTEM_ARCHITECTURE.md: topology, data-flow pipelines, the RLS/consent model, state management, external service contracts (Supabase, GROQ API, FCM, ABDM).
- Capture discovered engineering conventions in a NEW docs/ENGINEERING_GUIDELINES.md. If any belong in CLAUDE.md Section 13, propose them as approval-gated surgical additions per the Phase 1.5 rules.

PHASE 4 — Enhancement & refactoring (surgical only)
- Identify decoupling opportunities and performance issues (redundant rebuilds, N+1 queries, missing indexes on hot paths, unoptimized RLS helper calls, oversized widgets). Propose, justify, show the diff — apply nothing without approval.

Begin with Phase 0: analyze the repo structure and present your prioritized, high-level audit plan. Ask for confirmation before editing or adding any file.
