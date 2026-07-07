# Ayulekha — Flutter app

Single codebase for all three roles (Patient / Doctor-Clinic / Diagnostic Partner)
on mobile **and** web. Role-based routing from the three-button entry screen
(Section 2 of the root `CLAUDE.md`).

## First-time setup

The `lib/`, `pubspec.yaml`, and `test/` here are hand-authored. Platform folders
(`android/`, `ios/`, `web/`, etc.) are intentionally **not** committed — generate
them once with Flutter, which will not overwrite the existing `lib/`/`pubspec.yaml`:

```bash
cd app
flutter create .          # generates platform folders only; keeps lib/ & pubspec
flutter pub get
```

Then create your env files (never commit them — both are gitignored).

**Client `app/.env` — CLIENT-SAFE values only.** This file is bundled into the
app, so it must contain ONLY `SUPABASE_URL` + `SUPABASE_ANON_KEY` (the anon key is
publishable). It is a declared asset and **must exist for the build to succeed**:

```bash
cd app
printf 'SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\n' "https://YOUR-REF.supabase.co" "YOUR-ANON-KEY" > .env
```

**Root `./.env` — SERVER-ONLY secrets.** Never bundled into the client. Holds the
`SUPABASE_SERVICE_ROLE_KEY` (bypasses RLS) and future server secrets
(`SUPABASE_JWT_SECRET`, `ANTHROPIC_API_KEY`, `FCM_SERVER_KEY`). Used only for CLI
migrations, Edge Functions, and server scripts.

> ⚠️ Never put the service_role key (or any server secret) in `app/.env` — it would
> ship inside the client bundle and bypass all row-level security.

Run the app:

```bash
flutter run -d chrome     # web
flutter run               # connected mobile device/emulator
flutter test              # routing smoke test
```

## Structure

```
lib/
  core/
    config/   env flags (REQUIRE_ABHA), Supabase init
    theme/    shared theme + responsive breakpoints
    routing/  go_router: entry -> role flows
  features/
    entry/    three-button entry screen (Section 2)
    auth/
      patient/      phone+OTP placeholder (D3)
      clinic/       clinic login -> "Who are you?" -> PIN (D1) placeholders
      diagnostic/   flat lab login placeholder (Section 2.3)
  shared/
    widgets/  responsive scaffold, role button
    models/   enums + core data classes mirroring the schema
```

## Phase status

Phase 1 (scaffold + schema + placeholder auth) only. Real session scoping
(D1 PIN / D2 scoped JWT), consent flows, and features land in later phases per
Section 11 of `CLAUDE.md`.
