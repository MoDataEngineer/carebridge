// CareBridge — mint-scope-token Edge Function (D2, Phase 4.5 Option A).
//
// HS256 self-minting is GONE. Scope now travels inside the REAL asymmetric-signed
// GoTrue access token, injected by the custom_access_token_hook (migration 0007)
// from the scope_sessions row this function writes. Nothing here signs a JWT.
//
// Two actions:
//   { action: "login", registration_number, phone, otp }
//     -> resolves the clinic, ensures it has a GoTrue user (service-provisioned
//        email+password). The password is stored ENCRYPTED in Supabase Vault and
//        read back server-side only to sign in — never returned to the client,
//        never logged. Returns the real GoTrue session (access_token +
//        refresh_token) + the doctor roster. No scope yet.
//   { action: "scope", target_role: "doctor"|"admin", target_doctor_id?, pin,
//                       access_token }
//     -> verifies the PIN (server-only carebridge_verify_pin RPC), then UPSERTS
//        scope_sessions for the caller's auth user. The client then refreshes its
//        session; the new token carries clinic_id/active_role/active_doctor_id.
//
// REQUIRED SECRETS (supabase secrets set — never client-side):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
//   (SUPABASE_JWT_SECRET is no longer used.)
//
// DEPLOY: supabase functions deploy mint-scope-token

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Derived, stable login email for a clinic's GoTrue user. Internal only — clinics
// never see or use it; the real human-facing login is reg-number + phone/OTP.
const clinicEmail = (reg: string) =>
  `clinic.${reg.toLowerCase().replace(/[^a-z0-9]/g, "")}@carebridge.internal`;

const randomSecret = () =>
  // 32 url-safe bytes — used once per login then discarded.
  btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(0, 40) + "Aa1!";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---------------- action: login ----------------
  if (payload.action === "login") {
    const reg = String(payload.registration_number ?? "");
    // PLACEHOLDER: real phone/OTP verification lands in Phase 11.
    const { data: clinic, error: cErr } = await admin
      .from("clinics")
      .select("id, name, auth_user_id")
      .eq("registration_number", reg)
      .maybeSingle();
    if (cErr) return json({ error: "lookup_failed" }, 500);
    if (!clinic) return json({ error: "clinic_not_found" }, 404);

    const email = clinicEmail(reg);
    let authUserId = clinic.auth_user_id as string | null;
    let password: string;

    if (!authUserId) {
      // First login: provision the GoTrue user and store its password in Vault.
      password = randomSecret();
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { clinic_id: clinic.id, kind: "clinic" },
      });
      if (createErr || !created.user) return json({ error: "provision_failed" }, 500);
      authUserId = created.user.id;
      const { error: secErr } = await admin.rpc("carebridge_set_clinic_secret", {
        p_clinic_id: clinic.id,
        p_secret: password,
      });
      if (secErr) return json({ error: "secret_store_failed" }, 500);
      await admin.from("clinics").update({ auth_user_id: authUserId }).eq("id", clinic.id);
    } else {
      // Returning clinic: read the stored password from Vault (service-role only).
      const { data: stored, error: getErr } = await admin.rpc("carebridge_get_clinic_secret", {
        p_clinic_id: clinic.id,
      });
      if (getErr) return json({ error: "secret_read_failed" }, 500);
      if (stored) {
        password = stored as string;
      } else {
        // Self-heal a missing/lost secret: reset the password and re-store it.
        password = randomSecret();
        const { error: resetErr } = await admin.auth.admin.updateUserById(authUserId, { password });
        if (resetErr) return json({ error: "reset_failed" }, 500);
        const { error: secErr } = await admin.rpc("carebridge_set_clinic_secret", {
          p_clinic_id: clinic.id,
          p_secret: password,
        });
        if (secErr) return json({ error: "secret_store_failed" }, 500);
      }
    }

    // Clear any stale scope from a previous session so login starts unscoped.
    await admin.from("scope_sessions").delete().eq("auth_uid", authUserId);

    const { data: doctors, error: dErr } = await admin
      .from("doctors")
      .select("id, name, specialty")
      .eq("clinic_id", clinic.id)
      .eq("is_active", true)
      .order("name");
    if (dErr) return json({ error: "roster_failed" }, 500);

    // Sign in as the clinic user (anon client) to obtain a real GoTrue session.
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: session, error: sErr } =
      await userClient.auth.signInWithPassword({ email, password });
    if (sErr || !session.session) return json({ error: "signin_failed" }, 500);

    return json({
      clinic_id: clinic.id,
      clinic_name: clinic.name,
      doctors: doctors ?? [],
      is_solo: (doctors ?? []).length === 1,
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
      auth_user_id: authUserId,
    });
  }

  // ---------------- action: scope ----------------
  if (payload.action === "scope") {
    const role = String(payload.target_role ?? ""); // 'doctor' | 'admin'
    const doctorId = payload.target_doctor_id ? String(payload.target_doctor_id) : null;
    const pin = String(payload.pin ?? "");
    const accessToken = String(payload.access_token ?? "");

    if (role !== "doctor" && role !== "admin") return json({ error: "bad_role" }, 400);
    if (role === "doctor" && !doctorId) return json({ error: "doctor_id_required" }, 400);
    if (!accessToken) return json({ error: "missing_access_token" }, 400);

    // Identify the caller from their verified token, and resolve their clinic.
    const { data: userRes, error: uErr } = await admin.auth.getUser(accessToken);
    if (uErr || !userRes.user) return json({ error: "invalid_session" }, 401);
    const authUid = userRes.user.id;

    const { data: clinic, error: cErr } = await admin
      .from("clinics")
      .select("id")
      .eq("auth_user_id", authUid)
      .maybeSingle();
    if (cErr || !clinic) return json({ error: "clinic_not_found" }, 404);
    const clinicId = clinic.id as string;

    // If scoping to a doctor, that doctor must belong to THIS clinic (defence in
    // depth — the PIN check below also binds identity).
    if (role === "doctor") {
      const { data: doc } = await admin
        .from("doctors")
        .select("id")
        .eq("id", doctorId)
        .eq("clinic_id", clinicId)
        .eq("is_active", true)
        .maybeSingle();
      if (!doc) return json({ error: "doctor_not_in_clinic" }, 403);
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
      return json({
        error: "pin_rejected",
        reason: result?.reason ?? "bad_pin",
        locked_until: result?.locked_until ?? null,
      }, 401);
    }

    // Persist the verified scope. The custom_access_token_hook reads this row on
    // the next token issue/refresh and injects the claims RLS reads.
    const { error: upErr } = await admin.from("scope_sessions").upsert({
      auth_uid: authUid,
      clinic_id: clinicId,
      active_role: role,
      active_doctor_id: role === "doctor" ? doctorId : null,
      updated_at: new Date().toISOString(),
    });
    if (upErr) return json({ error: "scope_write_failed", detail: upErr.message }, 500);

    // The client must now refresh its session so the NEW token carries the scope.
    return json({
      ok: true,
      active_role: role,
      active_doctor_id: role === "doctor" ? doctorId : null,
      refresh_required: true,
    });
  }

  return json({ error: "unknown_action" }, 400);
});
