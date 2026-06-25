// CareBridge — ai-summary Edge Function (STUB, Phase 7)
//
// Purpose: one-touch AI summary (Section 8). Calls the Claude API SERVER-SIDE ONLY.
// Layer 1 (allergies/chronic/meds safety banner) is deterministic and NEVER AI-generated.
// Layer 2 narrative input: ONLY structured visit + test-result data — never raw notes/OCR/images.
//
// SAFETY (D6 + Section 8): summarize-only, never diagnosis/treatment under any prompt variation.
// The function MUST validate every returned sentence_sources visit_id/test_order_id against the
// actual input set and DROP hallucinated references before returning.
//
// REQUIRED TO MAKE REAL:
//   - ANTHROPIC_API_KEY (server-only secret), ANTHROPIC_MODEL (default claude-sonnet-4-6).

import { serve } from "https://deno.land/std/http/server.ts";

serve((_req) =>
  new Response(
    JSON.stringify({
      error: "not_implemented",
      phase: "Wired in Phase 7 — see CLAUDE.md §8. Needs ANTHROPIC_API_KEY. Summarize-only; validate source ids.",
    }),
    { status: 501, headers: { "Content-Type": "application/json" } },
  )
);
