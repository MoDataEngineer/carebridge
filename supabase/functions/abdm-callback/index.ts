// Ayulekha — abdm-callback Edge Function (Phase 11b).
//
// The HTTPS host ABDM's gateway calls back on (registered as the bridge URL).
// PUBLIC (verify_jwt = false in config.toml): ABDM calls it without a Supabase
// JWT. For sandbox onboarding this is a stub — it health-checks on GET and
// acknowledges callbacks with 202 (ABDM's async pattern), logging the body.
// The real HIP/HIU handlers (care-context discover/link, consent notify, data
// request) land here as the M1/M2/M3 milestones progress.

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Registration ping / health check.
  if (req.method === "GET") {
    return new Response(
      JSON.stringify({ status: "ok", service: "ayulekha-abdm-callback" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // ABDM callbacks: acknowledge asynchronously (202). We log method + path +
  // body SIZE only — never the body itself: ABDM callbacks carry health
  // identifiers / consent artefacts, and this is a public endpoint (security
  // review 2026-07-19, H3/M5). When the real per-path handlers land here they
  // MUST first verify ABDM's request signature before trusting any callback.
  let size = 0;
  try {
    size = (await req.text()).length;
  } catch {
    /* empty body is fine */
  }
  console.log(`[abdm-callback] ${req.method} ${url.pathname} (${size} bytes)`);
  return new Response("", { status: 202 });
});
