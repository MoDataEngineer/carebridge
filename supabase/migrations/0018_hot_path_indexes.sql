-- ============================================================
-- 0018: Hot-path partial indexes (audit Phase 4, item 1 — approved 2026-07-06)
--
-- Three read paths dominate:
--   1. The active-grant check inside current_scope_can_view_patient() — runs
--      for EVERY clinical-table RLS decision. The existing idx_grants_patient /
--      idx_grants_target indexes cover the full table; this partial composite
--      matches the exact predicate shape (patient + target + active only).
--   2. The follow-up tracker: a doctor's due/overdue visits.
--   3. The notification dispatcher: due, not-yet-sent rows every 10 minutes.
-- Indexes only — no behavior, RLS, or grant changes.
-- ============================================================

-- 1. Active-grant lookup (doctor scope: patient+type+target; admin scope
--    AC-8: patient+type with a doctors join — the leading columns serve both).
create index if not exists idx_grants_active_lookup
  on access_grants (patient_id, granted_to_type, granted_to_id)
  where status = 'active' and revoked_at is null;

-- 2. Follow-up tracker (Phase 9): per-doctor due/overdue follow-ups.
create index if not exists idx_visits_followup_due
  on visits (doctor_id, follow_up_date)
  where follow_up_date is not null and not follow_up_completed;

-- 3. Notification dispatcher: due rows not yet sent.
create index if not exists idx_notifications_due
  on notifications (scheduled_for)
  where sent_at is null;
