-- Ayulekha — roster edit + deactivate (spec §5.2: admin can edit a doctor and
-- deactivate, which is a SOFT delete — historical visits/prescriptions are
-- preserved via doctors.is_active, never a hard delete).
--
-- Same auth model as carebridge_add_doctor (0013/0023): the caller must BE the
-- clinic's GoTrue user (auth.uid() match) AND hold an admin-scoped session, and
-- the target doctor must belong to that clinic. Mirrors the ID-4 validation.

-- ------------------------------------------------------------
-- Edit a doctor's ID-4 fields (+ optional HPR, login phone, PIN reset).
-- A null p_pin leaves the existing PIN unchanged; a provided one resets it.
-- ------------------------------------------------------------
create or replace function carebridge_update_doctor(
  p_doctor       uuid,
  p_name         text,
  p_council_reg  text,
  p_council_name text,
  p_specialty    text,
  p_hpr          text default null,
  p_phone        text default null,
  p_pin          text default null
)
returns table (id uuid, name text, specialty text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_clinic uuid;
  v_phone  text;
  v_norm   text;
begin
  select c.id into v_clinic from clinics c where c.auth_user_id = auth.uid();
  if v_clinic is null then
    raise exception 'not a clinic session';
  end if;
  if current_active_role() <> 'admin' or current_clinic_id() <> v_clinic then
    raise exception 'editing a doctor requires an admin-scoped session';
  end if;
  -- The doctor must belong to THIS clinic (no cross-clinic edits).
  if not exists (select 1 from doctors d where d.id = p_doctor and d.clinic_id = v_clinic) then
    raise exception 'doctor not found in this clinic';
  end if;

  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_council_reg), '') = ''
     or coalesce(trim(p_council_name), '') = '' or coalesce(trim(p_specialty), '') = '' then
    raise exception 'name, council registration number, council name and specialty are required (ID-4)';
  end if;
  if p_pin is not null and p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'doctor PIN must be 4-6 digits';
  end if;

  -- Optional login phone: validate + ensure it does not collide with ANOTHER
  -- doctor (excluding this one, so re-saving an unchanged phone is fine).
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  if v_phone is not null then
    v_norm := right(regexp_replace(v_phone, '\D', '', 'g'), 10);
    if length(v_norm) < 10 then
      raise exception 'doctor mobile must be a valid 10-digit number';
    end if;
    if exists (
      select 1 from doctors d
      where d.id <> p_doctor
        and right(regexp_replace(d.phone, '\D', '', 'g'), 10) = v_norm
    ) then
      raise exception 'this mobile number is already registered to another doctor';
    end if;
  end if;

  update doctors set
    name               = trim(p_name),
    council_reg_number = trim(p_council_reg),
    council_name       = trim(p_council_name),
    specialty          = trim(p_specialty),
    hpr_id             = nullif(trim(coalesce(p_hpr, '')), ''),
    phone              = v_phone,
    pin_hash           = case when p_pin is null then pin_hash
                              else crypt(p_pin, gen_salt('bf')) end
  where id = p_doctor;

  return query select d.id, d.name, d.specialty from doctors d where d.id = p_doctor;
end;
$$;

-- ------------------------------------------------------------
-- Soft delete / restore: flip doctors.is_active. Visits stay intact.
-- ------------------------------------------------------------
create or replace function carebridge_set_doctor_active(
  p_doctor uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clinic uuid;
begin
  select c.id into v_clinic from clinics c where c.auth_user_id = auth.uid();
  if v_clinic is null then
    raise exception 'not a clinic session';
  end if;
  if current_active_role() <> 'admin' or current_clinic_id() <> v_clinic then
    raise exception 'changing a doctor''s status requires an admin-scoped session';
  end if;
  if not exists (select 1 from doctors d where d.id = p_doctor and d.clinic_id = v_clinic) then
    raise exception 'doctor not found in this clinic';
  end if;

  update doctors set is_active = p_active where id = p_doctor;
end;
$$;

grant execute on function carebridge_update_doctor(uuid, text, text, text, text, text, text, text) to authenticated;
grant execute on function carebridge_set_doctor_active(uuid, boolean) to authenticated;
