# Ayulekha — Engineering Guidelines (discovered conventions)

> Audit Phase 3 deliverable: the conventions the codebase actually follows,
> written down so future changes stay consistent. Complements CLAUDE.md
> Section 13 (Karpathy rules) — never overrides it.

## Database / SQL

1. **Every access decision lives in RLS or a SECURITY DEFINER function** —
   never only in Dart. New tables: enable RLS in the same migration, add
   explicit `grant` lines for `authenticated`, default-deny everything else.
2. **Definer functions**: `security definer` + `set search_path = public`
   (add `, extensions` only when using pgcrypto), authorize off verified
   claims (`current_*` helpers) in the first lines, `grant execute` to the
   narrowest role. Client-facing ones are named `carebridge_<verb>_<noun>`.
3. **Server-only functions** (PIN, vault, rate-limit): `revoke all … from
   public, anon, authenticated; grant execute … to service_role;`.
4. **Storage policies**: always qualify `objects.name` — an unqualified
   `name` inside a subquery that joins doctors/patients resolves to the
   person's name column and silently matches nothing (found via
   rls_storage.sql).
5. **Migrations are idempotent** (`create … if not exists`, `create or
   replace`, `drop policy if exists`) because the CLI applies them
   statement-by-statement; a re-run must be safe.
6. **Trust tests** (`supabase/tests/rls_*.sql`): one DO block; seed as owner;
   `set local role authenticated` + `set_config('request.jwt.claims', …,
   true)` to impersonate scopes; count-based assertions; END with
   `raise exception '<NAME>_OK :: …' using errcode='P0001'` so the seed rolls
   back — exit code 1 with the `_OK` marker IS the pass signal. When counting
   rows another scope owns (e.g. notifications), `reset role` first.
7. Applying SQL to the hosted DB: `supabase db query` runs ONE statement per
   call (prepared statements) — use the splitter script; it must respect
   `$$`-dollar-quoting and `--` line comments.

## Edge Functions (Deno)

8. Secrets via `Deno.env.get`, never hardcoded; multi-line/JSON secrets are
   stored **base64-encoded** (`*_B64`) because env-file escaping corrupts
   newlines in private keys.
9. Handle `OPTIONS` with shared CORS headers on any function a browser calls.
10. Functions callable only by the scheduler check an `x-cron-secret` header —
    do not compare against `SUPABASE_SERVICE_ROLE_KEY` (key format varies
    between legacy JWT and `sb_secret_`).
11. Forward the CALLER's JWT for data reads (`createClient(url, anon,
    {global: {headers: {Authorization}}})`) so RLS decides; use the service
    client only for server-owned writes (caches, queues, provisioning).
12. Treat LLM output as untrusted: defensive JSON extraction, validate every
    id against the real input set, clip/sanitize free-text before prompts.
13. Deploy with `--use-api` (no Docker on this machine). Supabase secret keys
    401 on browser-like User-Agents — server scripts set a custom UA.

## Flutter

14. **Repository pattern everywhere**: abstract class + `Supabase*` impl +
    Riverpod `Provider` that throws if Supabase is uninitialized; widget
    tests override the provider with a fake. Adding an abstract method means
    updating every fake in `app/test/` — the analyzer will list them.
15. Repositories never filter by scope — RLS decides rows. The only
    scope-driven UI decisions are visibility gates (`scope.canWrite`,
    `scope.paid`).
16. Async loads into local state: prefer `_docs == null ? spinner : …` with a
    `_load()` that checks `mounted` — a `FutureBuilder` whose future is
    swapped in `setState` inside dialog callbacks has burned us once.
17. Dialogs: `showDialog<bool>` + local `TextEditingController`s; act only on
    `== true`; snackbar failures, never silent catches (`catchError((_){})`
    is reserved for best-effort telemetry like access-log writes).
18. Widget tests that tap through flows set a tall surface
    (`tester.view.physicalSize = Size(1200, 2400)` + tear-downs) to avoid
    off-screen taps.
19. New user-visible strings follow the existing tone: plain language,
    no jargon, one sentence.

## Process / hygiene

20. Two-commit rhythm per phase: `Phase N (DB core): …` with SQL + trust
    tests first, then `Phase N (UI): …` with widgets + widget tests. Stop and
    summarize between phases (CLAUDE.md Section 11).
21. `flutter analyze` clean and ALL tests green before every commit; SQL
    harnesses re-run when the DB surface changed.
22. Secrets live in root `.env` (server-only, gitignored) or `app/.env`
    (client-safe only). Never in git, never printed to the terminal, never in
    commit messages. The pg_cron job embeds CRON_SECRET, so cron creation is
    deliberately NOT a committed migration.
23. Git: commit messages via a temp file (`git commit -F`) — inline `-m` with
    quotes breaks PowerShell arg parsing. Founder decisions that diverge from
    CLAUDE.md are recorded in the commit message and code comments with the
    date, pending formal Phase 1.5 doc reconciliation.
24. Ask the founder before ANY new dependency or paid service (CLAUDE.md
    Section 12); record approval in the commit message.
