// CareBridge — ai-summary Edge Function (Phase 7, Section 8).
//
// One-touch AI summary, two layers:
//   Layer 1 (safety banner) — deterministic; comes straight from the structured
//     input the DB assembles. This function NEVER lets the model produce it.
//   Layer 2 (narrative) — Claude API, SERVER-SIDE ONLY. Input is exactly what
//     carebridge_ai_summary_input() returns: structured visits + structured
//     test values. No free-text notes, no files (enforced in migration 0012).
//
// Authorization: the caller's scoped JWT is forwarded to PostgREST, so the
// SECURITY DEFINER input function applies the Section 7 grant check (doctor
// grant, or admin via AC-8) and writes the access_logs audit row. This function
// adds no access of its own — if the RPC refuses, the caller gets 403.
//
// Caching (Section 8 "regenerate automatically whenever a new visit OR test
// report is added"): the input JSON is hashed; if the fingerprint matches the
// cached ai_summaries row, the cached narrative is returned without calling the
// model. Any new visit/report changes the input, changes the hash, and forces
// a regeneration on the next request. Cache writes use the service role — the
// table has no client write policy.
//
// SAFETY (Section 8): summarize-only. The system prompt forbids diagnosis or
// treatment suggestions, and every sentence_sources id the model returns is
// validated against the real input set — hallucinated references are DROPPED.
//
// REQUIRED SECRETS (supabase secrets set …): ANTHROPIC_API_KEY.
// Optional: ANTHROPIC_MODEL (default claude-sonnet-4-6).

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-6";

// Exact system prompt from CLAUDE.md Section 8 — do not reword.
const SYSTEM_PROMPT =
  "You are summarizing a patient's medical visit history for a doctor about " +
  "to see them. Use ONLY the structured visit and test-result data provided " +
  "below — do not infer, assume, or add anything not explicitly present. " +
  "Write one short paragraph (3–5 sentences) covering: how many visits and " +
  "over what period, the main recurring issue if any, current/most recent " +
  "medication and since when, any notable structured test results, and " +
  "whether a follow-up was advised and whether it happened. If data looks " +
  "incomplete or contradictory, say so plainly instead of guessing. Do not " +
  "suggest a diagnosis or treatment — only summarize what already happened.";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

interface SentenceSource {
  sentence: string;
  visit_id?: string;
  test_order_id?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);

  let patientId: string | undefined;
  try {
    patientId = (await req.json())?.patient_id;
  } catch { /* fall through to the check below */ }
  if (!patientId) return json({ error: "patient_id_required" }, 400);

  // 1. Structured input via the caller's scoped JWT — the DB enforces the
  //    grant check (Section 7 / AC-8) and writes the audit log.
  const callerDb = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: input, error: inputErr } = await callerDb.rpc(
    "carebridge_ai_summary_input",
    { p_patient: patientId },
  );
  if (inputErr) return json({ error: "access_denied", detail: inputErr.message }, 403);

  const banner = input.banner; // Layer 1 — deterministic, passed through as-is.
  const fingerprint = await sha256(JSON.stringify(input));

  // 2. Cache check (service role; table is server-write-only).
  const serviceDb = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: cached } = await serviceDb
    .from("ai_summaries")
    .select("summary, model, input_fingerprint, generated_at")
    .eq("patient_id", patientId)
    .maybeSingle();
  if (cached && cached.input_fingerprint === fingerprint) {
    return json({ banner, ...cached.summary, model: cached.model,
      generated_at: cached.generated_at, cached: true });
  }

  if ((input.visits?.length ?? 0) === 0 && (input.tests?.length ?? 0) === 0) {
    return json({ banner, summary: null, sentence_sources: [],
      detail: "no structured visits or test results yet", cached: false });
  }

  if (!ANTHROPIC_API_KEY) {
    return json({ error: "not_configured",
      detail: "ANTHROPIC_API_KEY secret is not set on this project" }, 503);
  }

  // 3. Layer 2 — Claude API, structured input only.
  const userContent =
    "Structured visit and test-result data (JSON):\n" +
    JSON.stringify({ visits: input.visits, tests: input.tests }) +
    '\n\nRespond with ONLY a JSON object of the form ' +
    '{"summary": "...", "sentence_sources": [{"sentence": "...", ' +
    '"visit_id": "..."} | {"sentence": "...", "test_order_id": "..."}]} ' +
    "where each sentence_sources entry maps one sentence of the summary to the " +
    "visit_id or test_order_id it came from. Use only ids present in the data.";

  const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userContent }],
    }),
  });
  if (!anthropicRes.ok) {
    return json({ error: "model_error", detail: await anthropicRes.text() }, 502);
  }
  const modelReply = await anthropicRes.json();
  const rawText: string = modelReply.content?.[0]?.text ?? "";

  let parsed: { summary?: string; sentence_sources?: SentenceSource[] };
  try {
    // Tolerate a fenced or prefixed reply: extract the first {...} block.
    const match = rawText.match(/\{[\s\S]*\}/);
    parsed = JSON.parse(match ? match[0] : rawText);
  } catch {
    return json({ error: "model_error", detail: "unparseable model output" }, 502);
  }
  if (!parsed.summary) return json({ error: "model_error", detail: "no summary" }, 502);

  // 4. Validate sentence sources: DROP any id not in the actual input set.
  const visitIds = new Set((input.visits ?? []).map((v: { visit_id: string }) => v.visit_id));
  const testIds = new Set((input.tests ?? []).map((t: { test_order_id: string }) => t.test_order_id));
  const sources = (parsed.sentence_sources ?? []).filter((s) =>
    (s.visit_id && visitIds.has(s.visit_id)) ||
    (s.test_order_id && testIds.has(s.test_order_id)),
  );

  const summaryBody = { summary: parsed.summary, sentence_sources: sources };

  // 5. Cache the narrative (service role — clients cannot write this table).
  const { error: cacheErr } = await serviceDb.from("ai_summaries").upsert({
    patient_id: patientId,
    summary: summaryBody,
    model: MODEL,
    input_fingerprint: fingerprint,
    generated_at: new Date().toISOString(),
  });
  if (cacheErr) console.error("ai_summaries cache write failed:", cacheErr.message);

  return json({ banner, ...summaryBody, model: MODEL,
    generated_at: new Date().toISOString(), cached: false });
});
