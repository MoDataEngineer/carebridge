# CareBridge — Flutter app

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

Then create your env file (never commit it):

```bash
cp ../.env.example .env    # fill SUPABASE_URL / SUPABASE_ANON_KEY, keep REQUIRE_ABHA=false
```

The app boots in **placeholder mode** even without `.env` (falls back to
`.env.example`), so you can run the scaffold immediately:

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
