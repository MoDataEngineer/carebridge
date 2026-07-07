-- Ayulekha — per-doctor mobile login (founder enhancement 2026-07-07).
--
-- Problem: there is ONE login per hospital (registered mobile → OTP → "Who are
-- you?" → PIN). In a multi-doctor hospital that forced the admin to hand out the
-- hospital login to every doctor. Fix: a doctor gets their OWN mobile on the
-- roster; entering it on the hospital sign-in screen resolves their clinic and
-- pre-selects their identity, so they go straight to their own PIN + workspace.
--
-- Nothing about the auth/scope/RLS model changes: the doctor still authenticates
-- as the clinic's GoTrue user and is scoped by their PIN (D1/D2). This column
-- only adds a second RESOLUTION path for the mint-scope-token 'login' action.
-- Amends Section 2.2's "one login credential per clinic" — recorded as D13.

alter table doctors add column if not exists phone text;

-- A doctor's phone must resolve to exactly one doctor for login. Unique on the
-- normalized last-10 digits, only where set (existing rows stay null → excluded).
-- Cross-table collisions with a clinic phone are fine: the login action tries a
-- clinic match FIRST, so a solo doctor sharing the hospital number still works.
create unique index if not exists idx_doctors_phone_norm
  on doctors ((right(regexp_replace(phone, '\D', '', 'g'), 10)))
  where phone is not null;

-- Recreate carebridge_add_doctor with an optional p_phone. Same auth guard
-- (admin-scoped caller who IS the clinic user); validates + de-dupes the phone.
drop function if exists carebridge_add_doctor(text, text, text, text, text, text);

create or replace function carebridge_add_doctor(
  p_name         text,
  p_council_reg  text,
  p_council_name text,
  p_specialty    text,
  p_hpr          text default null,
  p_pin          text default null,
  p_phone        text default null
)
returns table (id uuid, name text, specialty text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_clinic uuid;
  v_doctor uuid;
  v_phone  text;
  v_norm   text;
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

  -- Optional login phone: validate + ensure it does not already resolve to
  -- another doctor (would make login ambiguous). Stored E.164-ish as given.
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  if v_phone is not null then
    v_norm := right(regexp_replace(v_phone, '\D', '', 'g'), 10);
    if length(v_norm) < 10 then
      raise exception 'doctor mobile must be a valid 10-digit number';
    end if;
    if exists (
      select 1 from doctors d
      where right(regexp_replace(d.phone, '\D', '', 'g'), 10) = v_norm
    ) then
      raise exception 'this mobile number is already registered to another doctor';
    end if;
  end if;

  insert into doctors (clinic_id, name, council_reg_number, council_name, specialty,
                       hpr_id, pin_hash, phone)
    values (v_clinic, trim(p_name), trim(p_council_reg), trim(p_council_name),
            trim(p_specialty), nullif(trim(coalesce(p_hpr, '')), ''),
            crypt(p_pin, gen_salt('bf')), v_phone)
    returning doctors.id into v_doctor;

  return query select d.id, d.name, d.specialty from doctors d where d.id = v_doctor;
end;
$$;

grant execute on function carebridge_add_doctor(text, text, text, text, text, text, text) to authenticated;
