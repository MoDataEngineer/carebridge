// Ayulekha — abdm-gateway Edge Function (Phase 11b, ABDM sandbox onboarding).
//
// Server-side ONLY. Holds the ABDM bridge credentials as Supabase secrets and
// talks to the ABDM gateway on the app's behalf. The client secret NEVER leaves
// the server: no action returns the raw session token.
//
// v3 gateway auth (per sandbox "WorkingWithABDMapi"):
//   POST {BASE}/api/hiecm/gateway/v3/sessions
//     headers: REQUEST-ID (uuid), TIMESTAMP (ISO), X-CM-ID (sbx)
//     body:    { clientId, clientSecret, grantType: "client_credentials" }
//     resp:    { accessToken, expiresIn, tokenType: "bearer", ... }
//   -> pass Authorization: Bearer <accessToken> on every later call.
//
// Bridge onboarding (sandbox devservice — the email's /gateway/v1/bridges path
// is deprecated and 403s with 900908 "subscription validation failed"):
//   PATCH {BASE}/devservice/v1/bridges                    body { url }
//   POST  {BASE}/devservice/v1/bridges/addUpdateServices  body [ service ]
//   GET   {BASE}/devservice/v1/bridges/getServices
// Sandbox-only; in production the bridge/services are configured via the HFR.
//
// REQUIRED SECRETS (supabase secrets set — never client-side, never committed):
//   ABDM_CLIENT_ID, ABDM_CLIENT_SECRET   (from the NHA approval)
// OPTIONAL:
//   ABDM_BASE_URL  (default https://dev.abdm.gov.in)
//   ABDM_CM_ID     (default sbx)
//
// DEPLOY: supabase functions deploy abdm-gateway

const BASE = (Deno.env.get("ABDM_BASE_URL") ?? "https://dev.abdm.gov.in").replace(/\/+$/, "");
const CLIENT_ID = Deno.env.get("ABDM_CLIENT_ID") ?? "";
const CLIENT_SECRET = Deno.env.get("ABDM_CLIENT_SECRET") ?? "";
const CM_ID = Deno.env.get("ABDM_CM_ID") ?? "sbx";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

// Standard ABDM headers for a call carrying the gateway session token.
function abdmHeaders(token?: string): Record<string, string> {
  const h: Record<string, string> = {
    "Content-Type": "application/json",
    "Accept": "*/*",
    "REQUEST-ID": crypto.randomUUID(),
    "TIMESTAMP": new Date().toISOString(),
    "X-CM-ID": CM_ID,
  };
  if (token) h["Authorization"] = `Bearer ${token}`;
  return h;
}

// Exchange client_id + client_secret for a gateway session token (v3).
async function getSessionToken(): Promise<string> {
  if (!CLIENT_ID || !CLIENT_SECRET) {
    throw new Error("ABDM_CLIENT_ID / ABDM_CLIENT_SECRET are not configured (set them as Supabase secrets).");
  }
  const res = await fetch(`${BASE}/api/hiecm/gateway/v3/sessions`, {
    method: "POST",
    headers: abdmHeaders(),
    body: JSON.stringify({
      clientId: CLIENT_ID,
      clientSecret: CLIENT_SECRET,
      grantType: "client_credentials",
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`session ${res.status}: ${text.slice(0, 300)}`);
  }
  const data = JSON.parse(text);
  if (!data.accessToken) throw new Error("session response had no accessToken");
  return data.accessToken as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch {
    /* some actions take no body */
  }
  const action = String(payload.action ?? "session");

  try {
    // --- session: prove the keys work WITHOUT leaking the token ---
    if (action === "session") {
      const token = await getSessionToken();
      return json({ ok: true, token_length: token.length, base: BASE, cm_id: CM_ID });
    }

    // --- get_services: view the bridge's registered services ---
    if (action === "get_services") {
      const token = await getSessionToken();
      const res = await fetch(`${BASE}/devservice/v1/bridges/getServices`, {
        method: "GET",
        headers: abdmHeaders(token),
      });
      const text = await res.text();
      return json({ status: res.status, body: safeJson(text) }, res.ok ? 200 : 502);
    }

    // --- patch_bridge_url: set the HTTPS host ABDM calls back on ---
    if (action === "patch_bridge_url") {
      const url = String(payload.url ?? "");
      if (!/^https:\/\/.+/.test(url)) return json({ error: "https_url_required" }, 400);
      const token = await getSessionToken();
      const res = await fetch(`${BASE}/devservice/v1/bridges`, {
        method: "PATCH",
        headers: abdmHeaders(token),
        body: JSON.stringify({ url }),
      });
      const text = await res.text();
      return json({ status: res.status, body: safeJson(text) }, res.ok ? 200 : 502);
    }

    // --- add_services: register HIP/HIU/PHR/Health-Locker services ---
    if (action === "add_services") {
      const services = payload.services;
      if (!Array.isArray(services)) return json({ error: "services_array_required" }, 400);
      const token = await getSessionToken();
      const res = await fetch(`${BASE}/devservice/v1/bridges/addUpdateServices`, {
        method: "POST",
        headers: abdmHeaders(token),
        body: JSON.stringify(services),
      });
      const text = await res.text();
      return json({ status: res.status, body: safeJson(text) }, res.ok ? 200 : 502);
    }

    // --- raw: probe an arbitrary path/method (onboarding diagnostics only) ---
    if (action === "raw") {
      const token = await getSessionToken();
      const path = String(payload.path ?? "");
      const method = String(payload.method ?? "GET");
      const extra = (payload.extra_headers ?? {}) as Record<string, string>;
      const res = await fetch(`${BASE}${path}`, {
        method,
        headers: { ...abdmHeaders(token), ...extra },
        body: payload.body != null ? JSON.stringify(payload.body) : undefined,
      });
      const text = await res.text();
      return json({ status: res.status, body: safeJson(text) });
    }

    return json({ error: "unknown_action", detail: action }, 400);
  } catch (e) {
    return json({ error: "abdm_call_failed", detail: String(e) }, 502);
  }
});

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text.slice(0, 500);
  }
}
