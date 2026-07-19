# Known issues / backlog

> **Security:** a full-codebase security audit (2026-07-19) lives in
> [`SECURITY_REVIEW_2026-07-19.md`](SECURITY_REVIEW_2026-07-19.md) — findings,
> prioritized fix list, and the demo/non-prod items to flip before production.

## OPEN — QR code renders as raw text + patient details fail to load from copied code (2026-07-18)

**Reported by founder during UI/UX modernization task (logged only — fix deliberately out of scope for that task).**

Repro steps:
1. Sign in as a patient (demo: mobile 9000000001) on the web build.
2. Privacy tab → "Share your record" → the overlay shows the code as plain
   text instead of a scannable QR image. Same on the Tests tab order cards.
3. Copy the 6-char share code, sign in as the doctor (Sunrise 9000000000 →
   Dr Priya PIN 1111), enter the code in patient search / claim.
4. Doctor side fails to load the patient's details after submitting the code.

Notes for the fixer:
- Real QR rendering landed in commit a6686e7 (qr_flutter, `CodeQr` widget in
  app/lib/shared/widgets/code_qr.dart, used by privacy_tab.dart and
  test_orders_view.dart). "Raw text" strongly suggests the tester was on a
  STALE cached web bundle — verify with a hard refresh (Ctrl+Shift+R) against
  the current `flutter build web --release` output before code-diving.
- "Patient details fail to load from the copied code" is a SEPARATE issue in
  the doctor-side consent-code claim path (Flow A). Reproduce and capture:
  the exact screen used, the RPC called (grep `carebridge_claim` /
  consent-code redemption in doctor_repository.dart), and the error surfaced.
  Check code expiry (short-lived by design) and case sensitivity of entry.

## Backlog (pre-ship, from 2026-07-18 audit)
- Doctor roster: edit + deactivate (spec §5.2) — only "add" exists.
- In-app PDF viewer for uploaded reports (images/structured already render).
- No-show / follow-up automated reminders (paid tier).
- Founder verification screen for new hospitals/labs (today: Supabase dashboard).
- Camera-based QR scanning on doctor/lab side (codes are typeable meanwhile).
