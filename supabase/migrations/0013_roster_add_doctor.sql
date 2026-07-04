-- CareBridge — hospital self-registration support: admin adds a doctor.
-- (Founder decision 2026-07-04: entry button renamed "Hospital"; hospitals
-- self-register, then create doctor profiles under themselves — same path for
-- solo doctors. Clinic creation itself happens in the mint-scope-token Edge
-- Function 'register' action, service-role side; THIS function is the
-- in-session roster add.)
--
-- Auth model: the caller must BE the clinic's GoTrue user (auth.uid() match)
-- AND hold an ADMIN-scoped session (roster management is admin-only, Section
-- 5.2). The doctor's PIN is hashed here with bcrypt — never stored plaintext,
-- mirroring carebridge_set_pin (0004).

create or replace function carebridge_add_doctor(
  p_name         text,
  p_council_reg  text,
  p_council_name text,
  p_specialty    text,
  p_hpr          text default null,
  p_pin          text default null
)
returns table (id uuid, name text, specialty text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_clinic uuid;
  v_doctor uuid;
begin
  -- Resolve the clinic from the VERIFIED auth user; never trust a client id.
  select c.id into v_clinic from clinics c where c.auth_user_id = auth.uid();
  if v_clinic is null then
    raise exception 'not a clinic session';
  end if;
  -- Roster management is admin-scoped (Section 5.2).
  if current_active_role() <> 'admin' or current_clinic_id() <> v_clinic then
    raise exception 'adding a doctor requires an admin-scoped session';
  end if;

  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_council_reg), '') = ''
     or coalesce(trim(p_council_name), '') = '' or coalesce(trim(p_specialty), '') = '' then
    raise exception 'name, council registration number, council name and specialty are required (ID-4)';
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'doctor PIN must be 4-6 digits';
  end if;

  insert into doctors (clinic_id, name, council_reg_number, council_name, specialty,
                       hpr_id, pin_hash)
    values (v_clinic, trim(p_name), trim(p_council_reg), trim(p_council_name),
            trim(p_specialty), nullif(trim(coalesce(p_hpr, '')), ''),
            crypt(p_pin, gen_salt('bf')))
    returning doctors.id into v_doctor;

  return query select d.id, d.name, d.specialty from doctors d where d.id = v_doctor;
end;
$$;

grant execute on function carebridge_add_doctor(text, text, text, text, text, text) to authenticated;
