// CareBridge — mint-scope-token Edge Function (D2).
//
// Two actions:
//   { action: "login",  registration_number, phone, otp }
//       -> verifies the clinic (OTP is PLACEHOLDER until Phase 11), returns a
//          BASE token { clinic_id, active_role: null } + the doctor roster so the
//          client can show "Who are you?" or auto-scope a solo clinic.
//   { action: "scope",  clinic_id, target_role: "doctor"|"admin",
//                        target_doctor_id?, pin }
//       -> verifies the PIN via the server-only carebridge_verify_pin RPC
//          (hashed + rate-limited) and, on success, mints a SHORT-LIVED SCOPED
//          token { clinic_id, active_role, active_doctor_id } that RLS reads.
//
// The scoped JWT is signed with SUPABASE_JWT_SECRET (HS256) so PostgREST accepts
// it and runs as the `authenticated` role. App state is never trusted for scope.
//
// REQUIRED SECRETS (set via `supabase secrets set`, never client-side):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_JWT_SECRET
//
// DEPLOY: `supabase functions deploy mint-scope-token`
//   (not deployed from this scaffold — see api-contracts.md).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const JWT_SECRET = Deno.env.get("SUPABASE_JWT_SECRET")!;

const TOKEN_TTL_SECONDS = 45 * 60; // 30–60 min per D2

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function signToken(claims: Record<string, unknown>): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(JWT_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return create(
    { alg: "HS256", typ: "JWT" },
    {
      ...claims,
      role: "authenticated",
      aud: "authenticated",
      iat: getNumericDate(0),
      exp: getNumericDate(TOKEN_TTL_SECONDS),
    },
    key,
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  // -------- action: login (clinic auth + roster + base token) --------
  if (payload.action === "login") {
    const reg = String(payload.registration_number ?? "");
    // PLACEHOLDER: real phone/OTP verification lands in Phase 11. For now we
    // resolve the clinic by its registration number only.
    const { data: clinic, error: cErr } = await admin
      .from("clinics")
      .select("id, name")
      .eq("registration_number", reg)
      .maybeSingle();
    if (cErr) return json({ error: "lookup_failed" }, 500);
    if (!clinic) return json({ error: "clinic_not_found" }, 404);

    const { data: doctors, error: dErr } = await admin
      .from("doctors")
      .select("id, name, specialty")
      .eq("clinic_id", clinic.id)
      .eq("is_active", true)
      .order("name");
    if (dErr) return json({ error: "roster_failed" }, 500);

    const baseToken = await signToken({
      sub: clinic.id,
      clinic_id: clinic.id,
      active_role: null,
      active_doctor_id: null,
    });

    return json({
      clinic_id: clinic.id,
      clinic_name: clinic.name,
      doctors: doctors ?? [],
      is_solo: (doctors ?? []).length === 1,
      base_token: baseToken,
    });
  }

  // -------- action: scope (PIN verify + scoped token) --------
  if (payload.action === "scope") {
    const clinicId = String(payload.clinic_id ?? "");
    const role = String(payload.target_role ?? ""); // 'doctor' | 'admin'
    const doctorId = payload.target_doctor_id ? String(payload.target_doctor_id) : null;
    const pin = String(payload.pin ?? "");

    if (role !== "doctor" && role !== "admin") {
      return json({ error: "bad_role" }, 400);
    }
    // AC-9: a doctor-scoped session must carry a specific doctor id.
    if (role === "doctor" && !doctorId) {
      return json({ error: "doctor_id_required" }, 400);
    }

    // Verify PIN against the right identity (server-only, rate-limited RPC).
    const verifyType = role === "admin" ? "admin" : "doctor";
    const verifyId = role === "admin" ? clinicId : doctorId;
    const { data: result, error: vErr } = await admin.rpc("carebridge_verify_pin", {
      p_type: verifyType,
      p_id: verifyId,
      p_pin: pin,
    });
    if (vErr) return json({ error: "verify_failed" }, 500);
    if (!result?.ok) {
      return json({ error: "pin_rejected", reason: result?.reason ?? "bad_pin", locked_until: result?.locked_until ?? null }, 401);
    }

    const scopedToken = await signToken({
      sub: clinicId,
      clinic_id: clinicId,
      active_role: role,
      active_doctor_id: role === "doctor" ? doctorId : null,
    });

    return json({
      access_token: scopedToken,
      expires_in: TOKEN_TTL_SECONDS,
      active_role: role,
      active_doctor_id: role === "doctor" ? doctorId : null,
    });
  }

  return json({ error: "unknown_action" }, 400);
});
