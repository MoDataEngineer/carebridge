-- ============================================================
-- 0031: Stop exposing doctors.pin_hash to clinic sessions.
-- Security review 2026-07-19, H2.
--
-- 0003 granted table-wide SELECT on `doctors` to `authenticated`. RLS filters
-- ROWS, not COLUMNS, so any clinic session that can see a doctor row could also
-- read that doctor's `pin_hash` (bcrypt of a short 4-6 digit PIN, offline-
-- crackable) — then scope a session as that doctor and write prescriptions
-- under their clinical identity (breaks CLAUDE.md 2.2 / 10 accountability).
--
-- Fix: replace the table-wide grant with an explicit column list that excludes
-- pin_hash. PIN verification runs only inside SECURITY DEFINER functions
-- (carebridge_verify_pin), which are unaffected by this grant.
-- ============================================================

revoke select on doctors from authenticated;

grant select (
  id,
  clinic_id,
  name,
  council_reg_number,
  council_name,
  specialty,
  hpr_id,
  hpr_verified,
  is_active,
  created_at,
  phone,
  photo_url
) on doctors to authenticated;
