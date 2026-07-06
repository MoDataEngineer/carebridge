-- CareBridge — founder enhancements 2026-07-06:
--   1. Hospitals carry state + city (patients filter the directory by place).
--   2. Hospital LOGIN is by mobile number alone (registration still records
--      the clinic registration/license number). Phones must therefore be
--      unique across clinics — enforced on the normalized last-10 digits.
--   3. Patients see trust signals: the doctor's council registration number
--      and an HPR "verified" badge (doctors.hpr_verified — founder-set until
--      the real HPR check lands in Phase 11b).

alter table clinics add column if not exists state text;
alter table clinics add column if not exists city  text;

-- Demo seed phones must be distinct for phone-only login (0017 gave both the
-- same number). Idempotent data fix, demo rows only.
update clinics set phone = '+919000000010'
  where registration_number = 'DEMO-002' and phone = '+919000000000';

-- One phone = one hospital (normalized to the last 10 digits).
create unique index if not exists idx_clinics_phone_norm
  on clinics ((right(regexp_replace(phone, '\D', '', 'g'), 10)))
  where phone is not null;

-- Booking directory now carries location + trust columns. Narrow on purpose:
-- names/specialty/license/badge only — never pin_hash or anything internal.
drop function if exists carebridge_bookable_doctors();
create or replace function carebridge_bookable_doctors()
returns table (
  doctor_id          uuid,
  doctor_name        text,
  specialty          text,
  council_reg_number text,
  council_name       text,
  hpr_verified       boolean,
  clinic_id          uuid,
  clinic_name        text,
  city               text,
  state              text
)
language sql
stable
security definer
set search_path = public
as $$
  select d.id, d.name, d.specialty, d.council_reg_number, d.council_name,
         coalesce(d.hpr_verified, false), c.id, c.name, c.city, c.state
  from doctors d
  join clinics c on c.id = d.clinic_id
  where d.is_active
  order by d.name
$$;

grant execute on function carebridge_bookable_doctors() to authenticated;
