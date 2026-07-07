# Ayulekha — Build Setup Guide (Windows, non-technical founder)

Goal: get from an empty machine to Claude Code actively building Ayulekha, phase by phase.
You install a few tools once; Claude Code runs the actual build commands for you and pauses for
your review after each phase. Budget ~1–1.5 hours for first-time setup.

---

## Stage 0 — Accounts you'll need

| Account | Why | When | Cost |
|---|---|---|---|
| **Claude Pro or Max** | Claude Code requires it — the free Claude.ai plan does **not** include Claude Code | Now | Paid subscription |
| **GitHub** | Stores your code; lets you (and the agent) track changes safely | Now | Free |
| **Supabase** | Your backend — database, auth, file storage | Stage 5 / Phase 1 | Free tier is enough to start |
| **Firebase** | Push notifications (FCM) | Later (Phase 8) | Free tier |
| **Anthropic API key** | Powers the AI summary Edge Function (server-side) | Later (Phase 7) | Pay-as-you-go |

> Only the first two are needed before you start. Create the others when the agent reaches that phase.

---

## Stage 1 — Install the tools (in this order)

1. **Git for Windows** — https://git-scm.com/downloads/win
   Required by both Claude Code (for its Bash tool) and Flutter. Accept the default options.

2. **Flutter SDK + Android Studio** — https://docs.flutter.dev/install (choose Windows)
   - Install the Flutter SDK and add it to your PATH (the installer/guide walks you through it).
   - Install **Android Studio** — it provides the Android emulator (a phone on your screen) and,
     via the Visual Studio "Desktop development with C++" workload, the build tools Flutter needs.
   - Minimum machine: Windows 10/11 64-bit, 8 GB RAM recommended, ~10 GB free disk.
   - After install, you (or the agent) can run `flutter doctor` to check everything is ready.

3. **VS Code** — https://code.visualstudio.com — your code editor. Add the Flutter extension.

4. **Claude Code** — pick ONE:
   - **Desktop app (recommended for you):** https://claude.com/download — graphical, no terminal
     needed for the AI part.
   - **Terminal install:** open **PowerShell** (not CMD) and run:
     ```powershell
     irm https://claude.ai/install.ps1 | iex
     ```
     Then close and reopen PowerShell and verify with `claude --version`.

> Tip: if `claude` "is not recognized" after install, close and reopen the terminal — the PATH
> updates only on a fresh window.

---

## Stage 2 — Put the project under Git + GitHub

Your spec files already live in the DoctorConnect folder. To version-control them:

1. Create a new **empty** repo on GitHub (e.g. `carebridge`), private.
2. In that folder, initialize git and push. You can simply ask Claude Code to do this for you:
   > "Initialize a git repo here, make the first commit with the existing files, and push it to my
   > GitHub repo at <paste the repo URL>."
3. Make sure these files are in the repo root: `CLAUDE.md`, `AGENTS.md` (a copy of CLAUDE.md),
   `DECISIONS.md`, `CLAUDE_CODE_KICKOFF.md`. (If `AGENTS.md` is missing, ask the agent to create it
   as an identical copy of `CLAUDE.md`.)

---

## Stage 3 — Start Claude Code on the project

- **Desktop app:** open it, then open the DoctorConnect folder as your project.
- **Terminal:** open the folder and run `claude`. First run opens a browser to log in with your
  Claude account.

Confirm the agent can see the spec by asking: *"List the files in this repo and confirm you've read
CLAUDE.md and DECISIONS.md."*

---

## Stage 4 — Kick off the build

Paste the **entire contents of `CLAUDE_CODE_KICKOFF.md`** as your first instruction.

The agent will:
1. Confirm it read `CLAUDE.md` + `DECISIONS.md` and restate the six settled decisions.
2. Propose the **Phase 1** plan: Flutter app shell with the three-button entry screen, the Supabase
   schema, and placeholder auth.
3. Wait for your "go".

Reply **"Approved, proceed with Phase 1"** and it starts building.

---

## Stage 5 — Connect Supabase (when Phase 1 needs it)

When the agent reaches the database step it will tell you it needs a Supabase project:
1. Create a project at https://supabase.com (pick a region near India, e.g. Mumbai/Singapore).
2. The agent will tell you exactly which values to copy (project URL, anon key, service-role key)
   and where to put them — these go in environment variables / Supabase secrets, **never** in the
   code. Don't paste secret keys into chat; follow the agent's file-based instructions.

---

## Stage 6 — Your working rhythm (the important part)

The build runs in **11 phases** (see Section 11 of `CLAUDE.md`). After each phase the agent stops
and summarizes. For each phase:

1. Read the agent's summary of what it built.
2. Ask it to **run the app** (`flutter run`) and show you the screen, or run its tests.
3. If something's off, describe what you expected — don't worry about the code itself.
4. When happy, say **"Approved, proceed to Phase N+1."**

Phases most worth slowing down on (the agent has been told to test these hard):
- **Phase 2** — clinic login, per-doctor PIN, the "Who are you?" picker, doctor-vs-admin scoping.
- **Phase 5** — the consent/access-grant flow and the admin inherited-visibility rule (AC-8).
- **Phase 6** — diagnostic-partner order-scoped grants (the lab sees only one order).

For each of these, ask the agent to **show you the passing tests** for the three trust cases listed
in `CLAUDE.md` Section 12.

---

## Stage 7 — One decision still open

When the agent reaches **Phase 9 (voice prescriptions)** it will ask you to confirm the
speech-to-text engine. Default recommendation: **on-device STT** for MVP (free, no patient data
leaves the phone). You can upgrade to a cloud engine later for better Indian drug-name accuracy.

---

## Quick troubleshooting

- **`claude` not recognized** → reopen the terminal; check `%USERPROFILE%\.local\bin` is in PATH.
- **`flutter doctor` shows red X's** → follow exactly what it says; usually a missing Android
  license (`flutter doctor --android-licenses`) or the C++ workload. You can paste the output to
  the agent and ask it to fix it.
- **Agent wants to add a paid service or new dependency** → it's been told to ask first; check it's
  something you actually want before approving.
- **You're unsure about anything the agent proposes** → tell it "explain this in plain language and
  the trade-offs" before approving. It will.
