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
// Bridge onboarding (exactly per the NHA approval email — auth token added,
// which the email's abbreviated curls omit):
//   PATCH {BASE}/gateway/v1/bridges                    body { url }
//   POST  {BASE}/gateway/v1/bridges/addUpdateServices  body [ service ]
//   GET   {BASE}/gateway/v1/bridges/getServices
// NOTE: with a valid gateway token this endpoint currently returns 900908
// ("API Subscription validation failed") — the bridge app is not subscribed to
// this API in the sandbox, or the path is retired ABDM-side. Resolve via the
// sandbox portal's app/API subscription, or NHA integration support.
//
// REQUIRED SECRETS (supabase secrets set — never client-side, never committed):
//   ABDM_CLIENT_ID, ABDM_CLIENT_SECRET   (from the NHA approval)
// OPTIONAL:
//   ABDM_BASE_URL  (default https://dev.abdm.gov.in)
//   ABDM_CM_ID     (default sbx)
//
// DEPLOY: supabase functions deploy abdm-gateway

const BASE = (Deno.env.get("ABDM_BASE_URL") ?? "https://dev.abdm.gov.in").replace(/\/+$/, "");
// M1 ABHA enrollment lives on a different host; the gateway session token still
// authorizes it.
const ABHA_BASE = (Deno.env.get("ABDM_ABHA_URL") ?? "https://abhasbx.abdm.gov.in/abha/api").replace(/\/+$/, "");
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

// ---- M1 ABHA: RSA-OAEP(SHA-1) encryption of Aadhaar/OTP with ABDM's cert ----
function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function abhaPublicKey(token: string): Promise<CryptoKey> {
  const res = await fetch(`${ABHA_BASE}/v3/profile/public/certificate`, {
    method: "GET",
    headers: abdmHeaders(token),
  });
  if (!res.ok) throw new Error(`cert ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const { publicKey } = await res.json();
  const b64 = String(publicKey).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return await crypto.subtle.importKey(
    "spki",
    b64ToBytes(b64),
    { name: "RSA-OAEP", hash: "SHA-1" }, // RSA/ECB/OAEPWithSHA-1AndMGF1Padding
    false,
    ["encrypt"],
  );
}

async function rsaEncrypt(key: CryptoKey, plaintext: string): Promise<string> {
  const ct = await crypto.subtle.encrypt({ name: "RSA-OAEP" }, key,
    new TextEncoder().encode(plaintext));
  return btoa(String.fromCharCode(...new Uint8Array(ct)));
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
      const res = await fetch(`${BASE}/gateway/v1/bridges/getServices`, {
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
      const res = await fetch(`${BASE}/gateway/v1/bridges`, {
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
      const res = await fetch(`${BASE}/gateway/v1/bridges/addUpdateServices`, {
        method: "POST",
        headers: abdmHeaders(token),
        body: JSON.stringify(services),
      });
      const text = await res.text();
      return json({ status: res.status, body: safeJson(text) }, res.ok ? 200 : 502);
    }

    // --- abha_cert: fetch ABDM's public certificate (inspect format) ---
    if (action === "abha_cert") {
      const token = await getSessionToken();
      const res = await fetch(`${ABHA_BASE}/v3/profile/public/certificate`, {
        method: "GET",
        headers: abdmHeaders(token),
      });
      const text = await res.text();
      return json({ status: res.status, length: text.length, preview: text.slice(0, 140) });
    }

    // --- abha_create_request_otp: Aadhaar -> OTP to Aadhaar-linked mobile ---
    // Raw Aadhaar is encrypted here and relayed; never stored (ID-6).
    if (action === "abha_create_request_otp") {
      const aadhaar = String(payload.aadhaar ?? "").replace(/\s/g, "");
      if (!/^\d{12}$/.test(aadhaar)) return json({ error: "aadhaar_12_digits_required" }, 400);
      const token = await getSessionToken();
      const key = await abhaPublicKey(token);
      const res = await fetch(`${ABHA_BASE}/v3/enrollment/request/otp`, {
        method: "POST",
        headers: abdmHeaders(token),
        body: JSON.stringify({
          txnId: "",
          scope: ["abha-enrol"],
          loginHint: "aadhaar",
          loginId: await rsaEncrypt(key, aadhaar),
          otpSystem: "aadhaar",
        }),
      });
      const text = await res.text();
      return json({ status: res.status, body: safeJson(text) }, res.ok ? 200 : 502);
    }

    // --- abha_create_verify: txnId + OTP -> creates the ABHA (profile+tokens) ---
    if (action === "abha_create_verify") {
      const txnId = String(payload.txnId ?? "");
      const otp = String(payload.otp ?? "");
      const mobile = String(payload.mobile ?? "");
      if (!txnId || !otp) return json({ error: "txnId_and_otp_required" }, 400);
      const token = await getSessionToken();
      const key = await abhaPublicKey(token);
      const res = await fetch(`${ABHA_BASE}/v3/enrollment/enrol/byAadhaar`, {
        method: "POST",
        headers: abdmHeaders(token),
        body: JSON.stringify({
          authData: {
            authMethods: ["otp"],
            otp: {
              timeStamp: new Date().toISOString(),
              txnId,
              otpValue: await rsaEncrypt(key, otp),
              mobile,
            },
          },
          consent: { code: "abha-enrollment", version: "1.4" },
        }),
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
