// CareBridge — notifications Edge Function (Phase 8).
//
// Invoked on a schedule (Supabase cron -> POST {job:"dispatch"}). Each run:
//   1. MEDICATION reminders: computes the current IST dose slot (morning /
//      afternoon / night from the D5 prescription schedule), finds active
//      prescriptions (visit_date + duration_days still running), and enqueues
//      ONE notifications row per patient per slot per day (deduped).
//   2. DISPATCH: sends every due row (scheduled_for <= now, sent_at null):
//      FCM v1 push to each of the patient's device_tokens when
//      FCM_SERVICE_ACCOUNT_JSON is configured; the in-app feed (RLS-read
//      notifications rows) works either way. Rows are marked sent_at.
//
// SECURITY: callable ONLY with the service-role key (cron), never by clients —
// clients read their feed via RLS, they never trigger sends.
//
// REQUIRED TO MAKE REAL (push): FCM_SERVICE_ACCOUNT_JSON — the Firebase
// service-account JSON (secret). Without it, dispatch still runs in-app-only.

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Preferred: base64-encoded service-account JSON (escape-proof for the \n
// sequences in private_key). Raw-JSON var kept as fallback.
const FCM_SA_JSON = (() => {
  const b64 = Deno.env.get("FCM_SERVICE_ACCOUNT_B64");
  if (b64) {
    try { return new TextDecoder().decode(Uint8Array.from(atob(b64.trim()), (c) => c.charCodeAt(0))); }
    catch (e) { console.error("FCM_SERVICE_ACCOUNT_B64 decode failed:", e); }
  }
  return Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
})();
// Shared secret for the scheduler (set via supabase secrets). Key formats vary
// (legacy JWT vs sb_secret_), so a dedicated header beats comparing keys.
const CRON_SECRET = Deno.env.get("CRON_SECRET");

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// IST dose slots (patients are in India): slot is active for 2h from its start.
const SLOTS: Record<string, number> = { morning: 8, afternoon: 14, night: 20 };
function currentIstSlot(): { slot: string; dateIst: string } | null {
  const ist = new Date(Date.now() + 5.5 * 3600 * 1000); // UTC+5:30
  const hour = ist.getUTCHours();
  const dateIst = ist.toISOString().slice(0, 10);
  for (const [slot, start] of Object.entries(SLOTS)) {
    if (hour >= start && hour < start + 2) return { slot, dateIst };
  }
  return null;
}

// ---- FCM v1: OAuth2 access token from the service account (RS256 JWT). ----
function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function fcmAccessToken(sa: { client_email: string; private_key: string }) {
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(enc.encode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now, exp: now + 3600,
  })));
  const pem = sa.private_key.replace(/-----[A-Z ]+-----|\n/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, enc.encode(`${header}.${claims}`)));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  if (!res.ok) throw new Error(`token exchange failed: ${await res.text()}`);
  return (await res.json()).access_token as string;
}

// Audit fix M1: push text carries NO PHI (no drug names, no test names) —
// lock screens and FCM transport see only generic prompts. The specifics live
// in the in-app feed, which is RLS-protected.
const TITLES: Record<string, (p: Record<string, unknown>) => [string, string]> = {
  appointment_reminder: () => ["Appointment tomorrow",
    "You have an appointment scheduled tomorrow. Tap to view details."],
  follow_up: () => ["Follow-up due today",
    "Your doctor advised a follow-up visit for today."],
  no_show: () => ["Missed appointment",
    "You missed a scheduled appointment — open Ayulekha to rebook."],
  report_ready: () => ["Test report ready",
    "A test report is ready — open Ayulekha to view it."],
  medication_reminder: (p) => ["Medication reminder",
    `Time for your ${p.slot ?? ""} dose — open Ayulekha for details.`],
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  // Scheduler only (cron); clients never call this. Requires the CRON_SECRET
  // shared secret in x-cron-secret (or the exact service key as Bearer).
  const auth = req.headers.get("Authorization") ?? "";
  const cronHeader = req.headers.get("x-cron-secret") ?? "";
  const authorized = (CRON_SECRET && cronHeader === CRON_SECRET) ||
    auth === `Bearer ${SERVICE_KEY}`;
  if (!authorized) return json({ error: "forbidden" }, 403);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const result = {
    medication_enqueued: 0, appointment_enqueued: 0, no_show_enqueued: 0,
    followup_enqueued: 0, dispatched: 0, pushed: 0, push_errors: 0,
  };

  // ---- 1. Medication reminders for the current IST slot ----
  const slotInfo = currentIstSlot();
  if (slotInfo) {
    const { slot, dateIst } = slotInfo;
    // Active prescriptions with this slot ticked (D5 structured schedule).
    const { data: rx } = await db
      .from("prescriptions")
      .select("drug_name, duration_days, schedule, visits!inner(patient_id, visit_date)")
      .filter("schedule->>" + slot, "eq", "true")
      .not("duration_days", "is", null);
    const byPatient = new Map<string, string[]>();
    for (const r of rx ?? []) {
      const v = r.visits as unknown as { patient_id: string; visit_date: string };
      const started = new Date(v.visit_date);
      const ends = new Date(started.getTime() + (r.duration_days as number) * 86400_000);
      if (ends < new Date()) continue; // course finished
      byPatient.set(v.patient_id, [...(byPatient.get(v.patient_id) ?? []), r.drug_name as string]);
    }
    for (const [patientId, drugs] of byPatient) {
      // Dedupe: one row per patient per slot per IST day.
      const { data: dup } = await db.from("notifications").select("id")
        .eq("patient_id", patientId).eq("type", "medication_reminder")
        .eq("payload->>date", dateIst).eq("payload->>slot", slot).limit(1);
      if (dup && dup.length > 0) continue;
      await db.from("notifications").insert({
        patient_id: patientId,
        type: "medication_reminder",
        payload: { date: dateIst, slot, drugs },
        scheduled_for: new Date().toISOString(),
      });
      result.medication_enqueued++;
    }
  }

  // ---- 1b. Appointment + no-show reminders ----
  // IST calendar dates (patients are in India). We classify each active
  // ('scheduled' = approved, not yet attended) appointment by its IST date:
  //   - tomorrow  -> a day-before "appointment_reminder"
  //   - in the past & still 'scheduled' (never checked in) -> a "no_show" nudge
  // Deduped per appointment so re-runs never double-send.
  const nowIst = new Date(Date.now() + 5.5 * 3600 * 1000);
  const todayIst = nowIst.toISOString().slice(0, 10);
  const tomorrowIst = new Date(nowIst.getTime() + 86400_000).toISOString().slice(0, 10);
  {
    const { data: appts } = await db
      .from("appointments")
      .select("id, patient_id, scheduled_time")
      .eq("status", "scheduled")
      .gte("scheduled_time", new Date(Date.now() - 3 * 86400_000).toISOString())
      .lte("scheduled_time", new Date(Date.now() + 3 * 86400_000).toISOString());
    for (const a of appts ?? []) {
      const istDate = new Date(new Date(a.scheduled_time as string).getTime() +
        5.5 * 3600_000).toISOString().slice(0, 10);
      let type: string | null = null;
      if (istDate === tomorrowIst) type = "appointment_reminder";
      else if (istDate < todayIst) type = "no_show";
      if (!type) continue;
      // Dedupe per appointment per type (one reminder, one no-show ever).
      const { data: dup } = await db.from("notifications").select("id")
        .eq("patient_id", a.patient_id).eq("type", type)
        .eq("payload->>appointment_id", a.id).limit(1);
      if (dup && dup.length > 0) continue;
      await db.from("notifications").insert({
        patient_id: a.patient_id,
        type,
        payload: { appointment_id: a.id, date: istDate },
        scheduled_for: new Date().toISOString(),
      });
      if (type === "no_show") result.no_show_enqueued++;
      else result.appointment_enqueued++;
    }
  }

  // ---- 1c. Follow-up-due reminders ----
  // Visits whose advised follow-up falls on today (IST) and isn't done yet.
  {
    const { data: visits } = await db
      .from("visits")
      .select("id, patient_id")
      .eq("follow_up_completed", false)
      .eq("follow_up_date", todayIst);
    for (const v of visits ?? []) {
      const { data: dup } = await db.from("notifications").select("id")
        .eq("patient_id", v.patient_id).eq("type", "follow_up")
        .eq("payload->>visit_id", v.id).eq("payload->>date", todayIst).limit(1);
      if (dup && dup.length > 0) continue;
      await db.from("notifications").insert({
        patient_id: v.patient_id,
        type: "follow_up",
        payload: { visit_id: v.id, date: todayIst },
        scheduled_for: new Date().toISOString(),
      });
      result.followup_enqueued++;
    }
  }

  // ---- 2. Dispatch everything due ----
  const { data: due, error: dueErr } = await db
    .from("notifications")
    .select("id, patient_id, type, payload")
    .is("sent_at", null)
    .lte("scheduled_for", new Date().toISOString())
    .limit(200);
  if (dueErr) return json({ error: "queue_read_failed", detail: dueErr.message }, 500);

  let fcmToken: string | null = null;
  if (FCM_SA_JSON && (due ?? []).length > 0) {
    try {
      const sa = JSON.parse(FCM_SA_JSON);
      fcmToken = await fcmAccessToken(sa);
      // deno-lint-ignore no-explicit-any
      (globalThis as any).__fcmProject = sa.project_id;
    } catch (e) {
      console.error("FCM auth failed (falling back to in-app only):", e);
    }
  }

  for (const n of due ?? []) {
    if (fcmToken) {
      // Patient's devices via their linked auth user.
      const { data: pat } = await db.from("patients")
        .select("auth_user_id").eq("id", n.patient_id).maybeSingle();
      if (pat?.auth_user_id) {
        const { data: tokens } = await db.from("device_tokens")
          .select("fcm_token").eq("auth_user_id", pat.auth_user_id);
        const [title, body] = (TITLES[n.type] ?? (() => ["CareBridge", "You have a new notification."]))(n.payload ?? {});
        for (const t of tokens ?? []) {
          // deno-lint-ignore no-explicit-any
          const project = (globalThis as any).__fcmProject;
          const res = await fetch(
            `https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
              method: "POST",
              headers: { Authorization: `Bearer ${fcmToken}`, "Content-Type": "application/json" },
              body: JSON.stringify({ message: {
                token: t.fcm_token,
                notification: { title, body },
                data: { type: n.type, notification_id: n.id },
              }}),
            });
          if (res.ok) result.pushed++;
          else { result.push_errors++; console.error("FCM send failed:", await res.text()); }
        }
      }
    }
    await db.from("notifications").update({ sent_at: new Date().toISOString() }).eq("id", n.id);
    result.dispatched++;
  }

  return json({ ok: true, fcm_configured: !!FCM_SA_JSON, ...result });
});
