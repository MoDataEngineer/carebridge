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

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// ---- Phase 11 (D12): custom OTP, Supabase-hosted (founder decision
// 2026-07-06 — Firebase SMS too costly for Indian volumes). Codes are
// generated/hashed/verified HERE (auth_otps table, 5-min expiry, 5 attempts,
// single use); only the SMS SEND is provider-specific. MSG91 first:
//   MSG91_AUTH_KEY + MSG91_TEMPLATE_ID  -> real SMS via the MSG91 flow API
//   (absent)                            -> OTP off; demo login continues
// REQUIRE_OTP gates whether a verified code is mandatory. It FAILS CLOSED
// (security review 2026-07-19, M1): default is "on" unless explicitly set to
// "false". The pre-incorporation demo posture (phone-only login, no MSG91 yet)
// stays available by setting REQUIRE_OTP=false in the function's secrets — but
// a production deploy that simply forgets the env var now refuses passwordless
// login instead of silently allowing it.
const MSG91_AUTH_KEY = Deno.env.get("MSG91_AUTH_KEY") ?? "";
const MSG91_TEMPLATE_ID = Deno.env.get("MSG91_TEMPLATE_ID") ?? "";
const OTP_CONFIGURED = MSG91_AUTH_KEY !== "" && MSG91_TEMPLATE_ID !== "";
const REQUIRE_OTP = (Deno.env.get("REQUIRE_OTP") ?? "true") !== "false";

const sha256 = async (s: string) => {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
};

// Verify a submitted OTP code for a phone (normalized last-10). Consumes the
// code on success; counts attempts on failure. Returns true only on a live,
// unconsumed, correct code.
// deno-lint-ignore no-explicit-any
async function otpValid(admin: any, phone10: string, code: unknown): Promise<boolean> {
  if (!code || !/^[0-9]{6}$/.test(String(code))) return false;
  const { data: row } = await admin.from("auth_otps").select("*").eq("phone", phone10).maybeSingle();
  if (!row || row.consumed || row.attempts >= 5) return false;
  if (new Date(row.expires_at).getTime() < Date.now()) return false;
  if (row.code_hash !== await sha256(String(code))) {
    await admin.from("auth_otps").update({ attempts: row.attempts + 1 }).eq("phone", phone10);
    return false;
  }
  await admin.from("auth_otps").update({ consumed: true }).eq("phone", phone10);
  return true;
}

// M3: this endpoint mints session tokens, so it must NOT answer every origin.
// Only echo Access-Control-Allow-Origin for an allowlisted app origin — a
// random site in a victim's browser then can't read the token JSON. Non-browser
// clients (the Flutter mobile app) send no Origin header, so they're unaffected.
// Configure prod/staging web origins via the ALLOWED_ORIGINS secret (comma-sep).
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ??
  "http://localhost:5000,http://127.0.0.1:5000")
  .split(",").map((s) => s.trim()).filter(Boolean);

const corsFor = (origin: string | null) => {
  const h: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, content-type, apikey, x-client-info",
    "Vary": "Origin",
  };
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    h["Access-Control-Allow-Origin"] = origin;
  }
  return h;
};

// Derived, stable login email for a clinic's GoTrue user. Internal only — clinics
// never see or use it; the real human-facing login is reg-number + phone/OTP.
const clinicEmail = (reg: string) =>
  `clinic.${reg.toLowerCase().replace(/[^a-z0-9]/g, "")}@carebridge.internal`;

const randomSecret = () =>
  // 32 url-safe bytes — used once per login then discarded.
  btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(0, 40) + "Aa1!";

// Normalize a phone for comparison: digits only, last 10 (Indian mobiles).
const normPhone = (p: unknown) =>
  String(p ?? "").replace(/\D/g, "").slice(-10);

// M2: the rate-limit key must come from an IP the caller can't forge. A client
// can set `x-forwarded-for` to anything, so the FIRST token is untrusted; the
// gateway sets `x-real-ip` to the actual peer, and appends the real client IP
// as the LAST entry of `x-forwarded-for`. Prefer x-real-ip, else the last XFF
// hop — never the client-supplied first token.
const clientIp = (req: Request): string => {
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    const parts = xff.split(",").map((s) => s.trim()).filter(Boolean);
    if (parts.length > 0) return parts[parts.length - 1];
  }
  return "unknown";
};

Deno.serve(async (req) => {
  const cors = corsFor(req.headers.get("origin"));
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json", ...cors },
    });

  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
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

  // Audit M3: per-IP rolling-window rate limit on login/register (the
  // unauthenticated actions). 20 attempts / 10 minutes per IP per action.
  // L2: `scope` is included too — it verifies a PIN, so it's a credential-
  // guessing surface (the per-identity 5-strike lockout already applies on top).
  if (payload.action === "login" || payload.action === "register" ||
      payload.action === "patient_login" || payload.action === "send_otp" ||
      payload.action === "partner_login" || payload.action === "partner_register" ||
      payload.action === "scope") {
    const ip = clientIp(req);
    const { data: allowed, error: rateErr } = await admin.rpc("carebridge_rate_ok", {
      p_key: `${payload.action}:${ip}`,
      p_max: 20,
    });
    if (rateErr) return json({ error: "rate_check_failed" }, 500);
    if (!allowed) return json({ error: "too_many_attempts" }, 429);
  }

  // ---------------- action: send_otp ----------------
  // D12: generate + store a hashed 6-digit code and send it via MSG91.
  // Responds otp_not_configured while MSG91 secrets are absent — the client
  // falls back to the demo path (only accepted while REQUIRE_OTP is off).
  if (payload.action === "send_otp") {
    if (!OTP_CONFIGURED) return json({ error: "otp_not_configured" }, 501);
    const phone10 = normPhone(payload.phone);
    if (phone10.length < 10) return json({ error: "valid_phone_required" }, 400);

    // Per-phone limit on top of the per-IP one above (SMS costs money).
    const { data: phoneOk } = await admin.rpc("carebridge_rate_ok", {
      p_key: `send_otp:${phone10}`, p_max: 5,
    });
    if (!phoneOk) return json({ error: "too_many_attempts" }, 429);

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const { error: storeErr } = await admin.from("auth_otps").upsert({
      phone: phone10,
      code_hash: await sha256(code),
      created_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      attempts: 0,
      consumed: false,
    });
    if (storeErr) return json({ error: "otp_store_failed" }, 500);

    const smsRes = await fetch("https://control.msg91.com/api/v5/flow/", {
      method: "POST",
      headers: { "Content-Type": "application/json", authkey: MSG91_AUTH_KEY },
      body: JSON.stringify({
        template_id: MSG91_TEMPLATE_ID,
        short_url: "0",
        recipients: [{ mobiles: `91${phone10}`, otp: code }],
      }),
    });
    if (!smsRes.ok) return json({ error: "sms_send_failed" }, 502);
    return json({ sent: true });
  }

  // ---------------- action: patient_login ----------------
  // PLACEHOLDER (Phase 11): the phone alone signs in — NO OTP is verified yet
  // (real ABDM/SMS OTP replaces this; flagged per Section 12 + D3). Finds or
  // creates the patient row (D3 phone-first), provisions/repairs a real GoTrue
  // user for it, and returns a session so the patient RLS policies apply.
  if (payload.action === "patient_login") {
    const phone10 = normPhone(payload.phone);
    if (phone10.length < 10) return json({ error: "valid_phone_required" }, 400);
    // D12: a valid single-use code proves control of the phone; without one
    // the demo path continues ONLY while REQUIRE_OTP is off.
    const codeOk = await otpValid(admin, phone10, payload.otp_code);
    if (!codeOk && (REQUIRE_OTP || payload.otp_code)) {
      return json({ error: "otp_rejected",
        detail: "the SMS code is wrong or expired" }, 401);
    }
    const phoneE164 = "+91" + phone10;

    // Find the patient by phone (stored formats vary — match on last 10).
    let { data: patient } = await admin
      .from("patients")
      .select("id, name, auth_user_id")
      .like("phone", `%${phone10}`)
      .limit(1)
      .maybeSingle();
    if (!patient) {
      // First sign-in: bootstrap a phone-keyed record (D3); profile fills it in.
      const { data: created, error: insErr } = await admin
        .from("patients")
        .insert({ name: "", phone: phoneE164 })
        .select("id, name, auth_user_id")
        .single();
      if (insErr) return json({ error: "signup_failed" }, 500);
      patient = created;
    }

    const email = `patient.${phone10}@carebridge.internal`;
    const password = randomSecret(); // one-time; reset on every login
    let authUserId = patient.auth_user_id as string | null;

    // Repair stale links (e.g. a seeded id that has no real GoTrue user).
    if (authUserId) {
      const { data: u, error: getErr } = await admin.auth.admin.getUserById(authUserId);
      if (getErr || !u?.user) authUserId = null;
    }
    if (!authUserId) {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { patient_id: patient.id, kind: "patient" },
      });
      if (createErr) {
        // The user may already exist from an earlier run — look it up.
        const { data: existingId } = await admin.rpc("carebridge_auth_user_by_email", {
          p_email: email,
        });
        if (!existingId) return json({ error: "provision_failed" }, 500);
        authUserId = existingId as string;
        const { error: pwErr } = await admin.auth.admin.updateUserById(authUserId, { password });
        if (pwErr) return json({ error: "reset_failed" }, 500);
      } else {
        authUserId = created.user!.id;
      }
    } else {
      const { error: pwErr } = await admin.auth.admin.updateUserById(authUserId, { password });
      if (pwErr) return json({ error: "reset_failed" }, 500);
    }
    await admin.from("patients").update({ auth_user_id: authUserId }).eq("id", patient.id);

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: session, error: sErr } =
      await userClient.auth.signInWithPassword({ email, password });
    if (sErr || !session.session) return json({ error: "signin_failed" }, 500);

    return json({
      placeholder: true, // no OTP verified — demo posture until Phase 11
      patient_id: patient.id,
      name: patient.name ?? "",
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
    });
  }

  // ---------------- action: register ----------------
  // Founder decision (2026-07-04): hospitals self-register — hospital name +
  // registration/license number + mobile + an ADMIN PIN — then add doctor
  // profiles under themselves. Same path for solo doctors. Falls through to
  // the login provisioning below on success.
  let registeredReg: string | null = null;
  if (payload.action === "register") {
    const name = String(payload.name ?? "").trim();
    const reg = String(payload.registration_number ?? "").trim();
    const adminPin = String(payload.admin_pin ?? "");
    const address = String(payload.address ?? "").trim() || null;
    // 2026-07-06: hospitals carry state + city (patient directory filters).
    const state = String(payload.state ?? "").trim();
    const city = String(payload.city ?? "").trim();
    if (!name || !reg) return json({ error: "name_and_registration_required" }, 400);
    if (!state || !city) return json({ error: "state_and_city_required" }, 400);
    if (!/^[0-9]{4,6}$/.test(adminPin)) return json({ error: "admin_pin_must_be_4_to_6_digits" }, 400);

    const { data: existing, error: exErr } = await admin
      .from("clinics").select("id").eq("registration_number", reg).maybeSingle();
    if (exErr) return json({ error: "lookup_failed" }, 500);
    if (existing) return json({ error: "registration_number_already_exists" }, 409);

    // 2026-07-06: login is by mobile ALONE, so one phone = one hospital.
    // H2: self-registered hospitals start UNVERIFIED (founder flips the flag).
    const phone10 = normPhone(payload.phone);
    if (phone10.length < 10) return json({ error: "valid_phone_required" }, 400);
    const { data: samePhone } = await admin
      .from("clinics").select("id").like("phone", `%${phone10}`).limit(1).maybeSingle();
    if (samePhone) return json({ error: "phone_already_registered",
      detail: "a hospital already signs in with this mobile number" }, 409);

    const { data: created, error: insErr } = await admin
      .from("clinics")
      .insert({ name, registration_number: reg, address, state, city,
                phone: String(payload.phone), verified: false })
      .select("id")
      .single();
    if (insErr) return json({ error: "register_failed" }, 500);

    // Hash + store the admin PIN server-side (bcrypt, migration 0004).
    const { error: pinErr } = await admin.rpc("carebridge_set_pin", {
      p_type: "admin", p_id: created.id, p_pin: adminPin,
    });
    if (pinErr) return json({ error: "pin_store_failed" }, 500);

    registeredReg = reg; // fall through to login provisioning
  }

  // ---------------- action: login (also completes register) ----------------
  // 2026-07-06: hospital login is by MOBILE alone (unique per clinic, 0022);
  // the registration/license number is collected once at registration.
  // 2026-07-07 (D13): the entered mobile also resolves a DOCTOR — if the number
  // is a doctor's own phone, we authenticate as that doctor's clinic user and
  // pre-select their identity so they skip "Who are you?" and go straight to
  // their PIN. Clinic (admin) match is tried FIRST, so a solo doctor sharing the
  // hospital number is unaffected.
  if (payload.action === "login" || registeredReg !== null) {
    const clinicCols =
      "id, name, registration_number, auth_user_id, subscription_status, phone, verified";
    let clinic: Record<string, unknown> | null = null;
    // A doctor-phone login pre-selects this identity (skips the picker).
    let preselectedDoctor: { id: string; name: string } | null = null;

    if (registeredReg !== null) {
      const { data, error: cErr } = await admin
        .from("clinics").select(clinicCols)
        .eq("registration_number", registeredReg).maybeSingle();
      if (cErr) return json({ error: "lookup_failed" }, 500);
      clinic = data;
    } else {
      const phone10 = normPhone(payload.phone);
      if (phone10.length < 10) return json({ error: "valid_phone_required" }, 400);
      // 1) hospital (admin) login — one phone = one clinic (0022).
      const { data: byClinic, error: cErr } = await admin
        .from("clinics").select(clinicCols)
        .like("phone", `%${phone10}`).maybeSingle();
      if (cErr) return json({ error: "lookup_failed" }, 500);
      clinic = byClinic;
      // 2) doctor self-login — the number is a doctor's own mobile (0023).
      if (!clinic) {
        const { data: doc } = await admin
          .from("doctors").select("id, name, clinic_id")
          .like("phone", `%${phone10}`).eq("is_active", true)
          .limit(1).maybeSingle();
        if (doc) {
          preselectedDoctor = { id: doc.id as string, name: (doc.name ?? "") as string };
          const { data: dClinic, error: dcErr } = await admin
            .from("clinics").select(clinicCols)
            .eq("id", doc.clinic_id).maybeSingle();
          if (dcErr) return json({ error: "lookup_failed" }, 500);
          clinic = dClinic;
        }
      }
    }
    if (!clinic) return json({ error: "clinic_not_found",
      detail: "no hospital or doctor signs in with this mobile number" }, 404);

    // Phase 11 D12 (closes audit H1 when enforced): a valid single-use OTP for
    // the ENTERED phone proves control of it (the doctor's own number for a
    // doctor login, the clinic's for a hospital login — both were matched by
    // it). Until REQUIRE_OTP is flipped, phone-only login stands (demo posture).
    // Skipped only when registration just happened in this same request.
    if (registeredReg === null) {
      const codeOk = await otpValid(admin, normPhone(payload.phone), payload.otp_code);
      if (!codeOk && (REQUIRE_OTP || payload.otp_code)) {
        return json({ error: "otp_rejected",
          detail: "the SMS code is wrong or expired" }, 401);
      }
    }

    // GoTrue email derives from the reg number — unchanged, so existing
    // clinic auth users keep working.
    const email = clinicEmail(clinic.registration_number as string);
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
      subscription_status: clinic.subscription_status ?? "free",
      verified: clinic.verified === true, // H2: badge in the app
      doctors: doctors ?? [],
      is_solo: (doctors ?? []).length === 1,
      // D13: set only for a doctor-phone login — the client skips the picker and
      // goes straight to this doctor's PIN entry.
      preselected_doctor_id: preselectedDoctor?.id ?? null,
      preselected_doctor_name: preselectedDoctor?.name ?? null,
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
      auth_user_id: authUserId,
    });
  }

  // ---------------- action: partner_register ----------------
  // Section 2.3 + ID-5: FLAT diagnostic-partner signup — lab name, type,
  // registration/license number (mandatory), phone, PIN; optional HFR/NABL.
  // Starts unverified (founder confirms the registration number, like H2).
  if (payload.action === "partner_register") {
    const name = String(payload.name ?? "").trim();
    const regNo = String(payload.registration_number ?? "").trim();
    const phone10 = normPhone(payload.phone);
    const pin = String(payload.pin ?? "");
    const type = String(payload.type ?? "both");
    if (!name || !regNo) return json({ error: "name_and_registration_required" }, 400);
    if (phone10.length < 10) return json({ error: "valid_phone_required" }, 400);
    if (!/^\d{4,8}$/.test(pin)) return json({ error: "pin_4_to_8_digits" }, 400);
    if (!["lab", "imaging", "both"].includes(type)) return json({ error: "bad_type" }, 400);

    const { data: existing } = await admin
      .from("diagnostic_partners").select("id")
      .or(`registration_number.eq.${regNo},phone.eq.+91${phone10}`)
      .maybeSingle();
    if (existing) return json({ error: "already_registered",
      detail: "a lab with this registration number or phone already exists — sign in instead" }, 409);

    const { data: created, error: insErr } = await admin
      .from("diagnostic_partners")
      .insert({
        name,
        type,
        registration_number: regNo,
        phone: `+91${phone10}`,
        hfr_id: payload.hfr_id ? String(payload.hfr_id).trim() : null,
        nabl_accredited: payload.nabl_accredited === true ? true : null,
        verified: false,
      })
      .select("id").single();
    if (insErr || !created) return json({ error: "register_failed" }, 500);

    const { error: pinErr } = await admin.rpc("carebridge_set_pin", {
      p_type: "partner", p_id: created.id, p_pin: pin,
    });
    if (pinErr) return json({ error: "pin_store_failed" }, 500);

    // Fall through to partner_login semantics via the shared sign-in below.
    payload.action = "partner_login";
    payload.registration_number = regNo;
    payload.pin = pin;
  }

  // ---------------- action: partner_login ----------------
  // Registration number + PIN -> real GoTrue session whose auth user is bound
  // to diagnostic_partners.auth_user_id, which current_partner_id() (0011) and
  // every Flow-C policy already key on. Same Vault password pattern as clinics.
  if (payload.action === "partner_login") {
    const regNo = String(payload.registration_number ?? "").trim();
    const pin = String(payload.pin ?? "");
    if (!regNo) return json({ error: "registration_number_required" }, 400);
    if (!pin) return json({ error: "pin_required" }, 400);

    const { data: partner, error: pErr } = await admin
      .from("diagnostic_partners")
      .select("id, name, type, registration_number, hfr_id, nabl_accredited, verified, auth_user_id")
      .eq("registration_number", regNo)
      .maybeSingle();
    if (pErr) return json({ error: "lookup_failed" }, 500);
    if (!partner) return json({ error: "partner_not_found",
      detail: "no lab is registered with this number" }, 404);

    // PIN check — server-only RPC, bcrypt + 5-strike lockout (0028).
    const { data: result, error: vErr } = await admin.rpc("carebridge_verify_pin", {
      p_type: "partner", p_id: partner.id, p_pin: pin,
    });
    if (vErr) return json({ error: "verify_failed" }, 500);
    if (!result?.ok) {
      return json({
        error: "pin_rejected",
        reason: result?.reason ?? "bad_pin",
        locked_until: result?.locked_until ?? null,
      }, 401);
    }

    const email = `partner.${regNo.toLowerCase().replace(/[^a-z0-9]/g, "")}@carebridge.internal`;
    let authUserId = partner.auth_user_id as string | null;
    let password: string;

    if (!authUserId) {
      password = randomSecret();
      const { data: createdUser, error: createErr } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { partner_id: partner.id, kind: "diagnostic_partner" },
      });
      if (createErr || !createdUser.user) return json({ error: "provision_failed" }, 500);
      authUserId = createdUser.user.id;
      const { error: secErr } = await admin.rpc("carebridge_set_partner_secret", {
        p_partner_id: partner.id, p_secret: password,
      });
      if (secErr) return json({ error: "secret_store_failed" }, 500);
      await admin.from("diagnostic_partners")
        .update({ auth_user_id: authUserId }).eq("id", partner.id);
    } else {
      const { data: stored, error: getErr } = await admin.rpc("carebridge_get_partner_secret", {
        p_partner_id: partner.id,
      });
      if (getErr) return json({ error: "secret_read_failed" }, 500);
      if (stored) {
        password = stored as string;
      } else {
        password = randomSecret();
        const { error: resetErr } = await admin.auth.admin.updateUserById(authUserId, { password });
        if (resetErr) return json({ error: "reset_failed" }, 500);
        const { error: secErr } = await admin.rpc("carebridge_set_partner_secret", {
          p_partner_id: partner.id, p_secret: password,
        });
        if (secErr) return json({ error: "secret_store_failed" }, 500);
      }
    }

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: session, error: sErr } =
      await userClient.auth.signInWithPassword({ email, password });
    if (sErr || !session.session) return json({ error: "signin_failed" }, 500);

    return json({
      partner_id: partner.id,
      partner_name: partner.name,
      type: partner.type,
      hfr_id: partner.hfr_id,
      nabl_accredited: partner.nabl_accredited === true,
      verified: partner.verified === true,
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
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
