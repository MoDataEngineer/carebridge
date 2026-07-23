# Known issues / backlog

> **Security:** a full-codebase security audit (2026-07-19) lives in
> [`SECURITY_REVIEW_2026-07-19.md`](SECURITY_REVIEW_2026-07-19.md) — findings,
> prioritized fix list, and the demo/non-prod items to flip before production.

## RESOLVED — QR raw text + patient details fail to load from copied code (fixed 2026-07-19)

Two separate causes, both addressed:

1. **"QR renders as raw text"** — was a STALE cached web bundle. The `CodeQr`
   widget (app/lib/shared/widgets/code_qr.dart) has rendered a real scannable
   QR via `qr_flutter` since commit a6686e7. Confirmed correct on a fresh
   `flutter build web --release --csp --no-web-resources-cdn`. No code change.

2. **"Doctor side fails to load patient details after entering the code"** — the
   real bug. `carebridge_redeem_consent_code` created the grant and returned the
   patient id correctly, but the doctor UI **discarded** that id and only showed
   "search to open the patient". In person the doctor rarely knows the patient's
   exact stored name/phone, so the follow-up search came up empty → "can't load
   the patient". Fix: the redeem dialog now returns the patient id and the
   workspace opens that record directly (access_flow_dialogs.dart,
   doctor_workspace_screen.dart, doctor_repository.dart `patientById`).
   Regression test: doctor_core_test.dart "redeeming a consent code opens the
   patient directly". The code itself is 16-char lowercase hex, 10-min expiry —
   no case-sensitivity issue.

## Backlog (pre-ship, from 2026-07-18 audit)
- ~~Doctor roster: edit + deactivate (spec §5.2)~~ — DONE (commit 2927fe4).
- ~~In-app PDF viewer for uploaded reports~~ — DONE: pdfx on mobile, native
  <iframe> on web (report_pdf_view*.dart). pdfx's own web renderer (pdf.js via
  CDN) is intentionally unused — it conflicts with the L4 CSP.
- ~~No-show / follow-up automated reminders~~ — DONE: the notifications cron
  now auto-enqueues appointment-tomorrow, no-show (past 'scheduled' appts), and
  follow-up-due reminders (supabase/functions/notifications). In-app feed works
  regardless of FCM; push needs FCM_SERVICE_ACCOUNT + the dashboard cron running.
- ~~Camera-based QR scanning on doctor/lab side~~ — DONE: mobile_scanner adds a
  "Scan QR code" option to the doctor consent-code dialog and the lab order-claim
  dialog on mobile/tablet (scan_code_screen.dart). Web keeps manual entry (no
  camera dependency invoked there). Manual typing remains everywhere as fallback.
- Founder verification screen for new hospitals/labs — DEFERRED to post-
  incorporation (founder is the only approver pre-launch; Supabase dashboard
  `UPDATE clinics SET verified=true` is the interim step; needs a new
  founder/platform-admin auth path to build properly).
