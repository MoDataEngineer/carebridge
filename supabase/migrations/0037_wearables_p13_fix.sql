-- CareBridge — Wearables P13 fix: carebridge_patient_wearables must be VOLATILE.
--
-- 0036 declared it STABLE, but it calls carebridge_log_view() which INSERTs the
-- audit row ('wearable data') into access_logs. A STABLE function runs in a
-- read-only transaction, so that INSERT failed at runtime with
-- "cannot execute INSERT in a read-only transaction" (SQLSTATE 25006) once the
-- grant + paid gates passed. Redefine as VOLATILE (the default) so the audit
-- write succeeds. Body is otherwise identical to 0036.

create or replace function carebridge_patient_wearables(p_patient uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.current_scope_can_view_wearables(p_patient) then
    raise exception 'no wearable share from this patient';
  end if;

  if not public.current_clinic_is_paid() then
    raise exception 'wearable trends are a paid feature';
  end if;

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
