// Ayulekha — branding-upload Edge Function (2026-07-19).
//
// Uploads a doctor photo / clinic logo into the public 'branding' bucket and
// saves the URL on the row. Runs with the SERVICE ROLE because client-side
// storage RLS proved unreliable for this project's storage service (uploads
// 403'd even under a with-check-true policy — see 0030 notes); the scope
// check happens HERE instead: the caller's verified JWT must belong to the
// clinic (clinics.auth_user_id), and a doctor photo must target a doctor of
// that clinic. Images are non-PHI branding assets.
//
// Input JSON: { doctor_id?: string|null, ext: "png"|"jpg"|"jpeg"|"webp",
//               data: base64 } (~max 1.5 MB decoded)
// Output: { url }

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Identify the caller from the verified JWT (verify_jwt=true guarantees one).
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userRes, error: uErr } = await admin.auth.getUser(token);
  if (uErr || !userRes.user) return json({ error: "invalid_session" }, 401);

  const { data: clinic } = await admin
    .from("clinics").select("id")
    .eq("auth_user_id", userRes.user.id).maybeSingle();
  if (!clinic) return json({ error: "clinic_session_required" }, 403);

  let payload: { doctor_id?: string | null; ext?: string; data?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const ext = String(payload.ext ?? "png").toLowerCase().replace(/[^a-z]/g, "");
  if (!["png", "jpg", "jpeg", "webp"].includes(ext)) {
    return json({ error: "unsupported_image_type" }, 400);
  }
  const b64 = String(payload.data ?? "");
  if (!b64) return json({ error: "data_required" }, 400);
  let bytes: Uint8Array;
  try {
    const bin = atob(b64);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch {
    return json({ error: "bad_base64" }, 400);
  }
  if (bytes.length > 1_500_000) return json({ error: "image_too_large_1500kb" }, 413);

  const doctorId = payload.doctor_id ? String(payload.doctor_id) : null;
  if (doctorId) {
    const { data: doc } = await admin
      .from("doctors").select("id")
      .eq("id", doctorId).eq("clinic_id", clinic.id).maybeSingle();
    if (!doc) return json({ error: "doctor_not_in_clinic" }, 403);
  }

  const path = `${clinic.id}/${doctorId ?? "clinic-logo"}.${ext}`;
  const contentType = `image/${ext === "jpg" ? "jpeg" : ext}`;
  const { error: upErr } = await admin.storage.from("branding")
    .upload(path, bytes, { upsert: true, contentType });
  if (upErr) return json({ error: "upload_failed", detail: upErr.message }, 500);

  const url = `${admin.storage.from("branding").getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;
  if (doctorId) {
    await admin.from("doctors").update({ photo_url: url }).eq("id", doctorId);
  } else {
    await admin.from("clinics").update({ logo_url: url }).eq("id", clinic.id);
  }
  return json({ url });
});
