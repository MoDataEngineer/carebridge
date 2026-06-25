// CareBridge — mint-scope-token Edge Function (STUB, Phase 1)
// Wired for real in Phase 2 (D2).
//
// Purpose: after clinic login + successful PIN entry (D1), mint a SHORT-LIVED scoped JWT:
//   { clinic_id, active_role: "doctor" | "admin", active_doctor_id: <uuid|null> }
// RLS policies read these claims — client app state is NEVER trusted for access decisions.
//
// REQUIRED TO MAKE REAL:
//   - SUPABASE_JWT_SECRET (server-only) to sign the token.
//   - Verify the submitted PIN against doctors.pin_hash / clinics.admin_pin_hash (hashed, rate-limited).
//   - Short TTL (30–60 min) with silent refresh while the PIN-backed session is active.

import { serve } from "https://deno.land/std/http/server.ts";

serve((_req) =>
  new Response(
    JSON.stringify({
      error: "not_implemented",
      phase: "Wired in Phase 2 — see DECISIONS.md D2. Needs SUPABASE_JWT_SECRET + PIN verification.",
    }),
    { status: 501, headers: { "Content-Type": "application/json" } },
  )
);
