-- CareBridge — Phase 5: doctor-side patient lookup to INITIATE Flow B.
-- A doctor can't see a patient they have no grant for (RLS), so they can't get
-- the patient_id needed to request access. This SECURITY DEFINER function lets a
-- doctor-scoped session resolve a patient by EXACT phone or ABHA only (no fuzzy
-- search → no enumeration), returning the minimum needed to send a request. It
-- does NOT expose any clinical data — just id + name + phone for the match.

create or replace function carebridge_lookup_patient_for_request(p_query text)
returns table (id uuid, name text, phone text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.name, p.phone
  from patients p
  where current_active_role() = 'doctor'
    and current_active_doctor_id() is not null
    and (p.phone = p_query or p.abha_id = p_query)   -- exact match only
  limit 5
$$;

revoke all on function carebridge_lookup_patient_for_request(text) from public, anon;
grant execute on function carebridge_lookup_patient_for_request(text) to authenticated;
