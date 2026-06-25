// CareBridge — notifications Edge Function (STUB, Phase 8)
//
// Purpose: scheduled reminders + report-ready notifications via Firebase Cloud Messaging.
//   - Appointment reminders, medication reminders (from D5 prescription schedule), follow-up,
//     and report-ready pushes.
//
// REQUIRED TO MAKE REAL:
//   - FCM_SERVER_KEY + FCM_PROJECT_ID (server-only). Device tokens stored per patient.

import { serve } from "https://deno.land/std/http/server.ts";

serve((_req) =>
  new Response(
    JSON.stringify({
      error: "not_implemented",
      phase: "Wired in Phase 8 — see CLAUDE.md §11. Needs FCM_SERVER_KEY + FCM_PROJECT_ID.",
    }),
    { status: 501, headers: { "Content-Type": "application/json" } },
  )
);
