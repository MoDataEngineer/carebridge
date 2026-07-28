-- CareBridge — Wearables epic (D14), Phase 13: doctor trend/adherence view.
--
-- Adds the doctor-facing read path for a patient's vitals, plus structured
-- visit advice for the actual-vs-target overlay. Trust guarantees enforced here,
-- server-side (CLAUDE.md §15):
--   * a doctor sees wearables ONLY with an active 'wearable' grant
--     (current_scope_can_view_wearables — NOT the generic patient helper, so a
--      clinical grant alone never reveals vitals);
--   * clinic admin AC-8 does NOT apply (the helper has no admin branch);
--   * PAID gating is enforced in the DB (current_clinic_is_paid), not just the UI;
--   * every read is logged to access_logs as 'wearable data'.

-- Structured visit advice for the adherence overlay (e.g.
-- {"activity_minutes_target": 30, "days_per_week": 5, "note": "brisk walk"}).
-- Written by the ordering doctor at visit time; optional.
alter table visits add column if not exists advice jsonb;

-- Single doctor entry point for a patient's vitals. SECURITY DEFINER so it can
-- read the wearable tables + write the audit log, but it re-checks the grant,
-- paid tier and clinic scope itself before returning anything.
create or replace function carebridge_patient_wearables(p_patient uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  -- Grant gate: an active 'wearable' grant to THIS doctor. A clinical grant
  -- fails this check; an admin session fails it (no admin branch in the helper).
  if not public.current_scope_can_view_wearables(p_patient) then
    raise exception 'no wearable share from this patient';
  end if;

  -- Paid gate (Section 9) — enforced server-side, not just in the app.
  if not public.current_clinic_is_paid() then
    raise exception 'wearable trends are a paid feature';
  end if;

  -- Audit: the patient sees this under "Who viewed my records".
  perform carebridge_log_view(p_patient, 'wearable data');

  select jsonb_build_object(
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object(
        'metric_type', metric_type, 'metric_date', metric_date, 'value', value)
        order by metric_date)
      from wearable_metrics_daily
      where patient_id = p_patient and metric_date >= (now()::date - 30)
    ), '[]'::jsonb),
    'workouts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', type, 'started_at', started_at, 'duration_min', duration_min,
        'distance_m', distance_m, 'calories', calories)
        order by started_at desc)
      from wearable_workouts
      where patient_id = p_patient and started_at >= now() - interval '30 days'
    ), '[]'::jsonb),
    -- Latest advice from a visit in THIS doctor's clinic, for the overlay.
    'advice', (
      select jsonb_build_object(
        'advice', advice, 'visit_date', visit_date, 'follow_up_date', follow_up_date)
      from visits
      where patient_id = p_patient
        and clinic_id = current_clinic_id()
        and advice is not null
      order by visit_date desc
      limit 1
    )
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function carebridge_patient_wearables(uuid) to authenticated;
