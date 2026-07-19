-- Ayulekha — doctor/clinic branding (UI modernization, 2026-07-19).
-- Doctor personal photo + hospital/clinic logo, uploadable by the clinic and
-- shown on the patient-facing doctor cards, booking confirmation, and the
-- doctor's own workspace header. Non-PHI marketing assets -> a PUBLIC-read
-- 'branding' bucket (uploads still require an authenticated session; each
-- clinic writes only under its own clinic-id folder, enforced by policy).

alter table doctors add column if not exists photo_url text;
alter table clinics add column if not exists logo_url  text;

insert into storage.buckets (id, name, public)
  values ('branding', 'branding', true)
on conflict (id) do nothing;

-- Authenticated clinic sessions upload/replace under branding/<clinic_id>/...
-- NOTE (bug found 2026-07-19): the storage service forwards only standard JWT
-- claims (sub/role) — current_clinic_id() is null there — AND a policy
-- subquery on clinics runs under the caller's RLS, whose policies need those
-- same custom claims. So the check must be a SECURITY DEFINER helper keyed on
-- auth.uid() alone.
create or replace function public.branding_folder_allowed(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from clinics c
    where c.auth_user_id = auth.uid() and c.id::text = p_folder
  );
$$;

grant execute on function public.branding_folder_allowed(text) to authenticated;

drop policy if exists branding_insert_own_clinic on storage.objects;
create policy branding_insert_own_clinic on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'branding'
    and public.branding_folder_allowed((storage.foldername(name))[1])
  );

drop policy if exists branding_update_own_clinic on storage.objects;
create policy branding_update_own_clinic on storage.objects
  for update to authenticated
  using (
    bucket_id = 'branding'
    and public.branding_folder_allowed((storage.foldername(name))[1])
  );

-- Patient directory now carries the branding (return type changes -> recreate).
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
  state              text,
  photo_url          text,
  logo_url           text
)
language sql
stable
security definer
set search_path = public
as $$
  select d.id, d.name, d.specialty, d.council_reg_number, d.council_name,
         coalesce(d.hpr_verified, false), c.id, c.name, c.city, c.state,
         d.photo_url, c.logo_url
  from doctors d
  join clinics c on c.id = d.clinic_id
  where d.is_active
  order by d.name
$$;

grant execute on function carebridge_bookable_doctors() to authenticated;

-- Clinic-side write path: set the URLs after an upload (own scope only).
create or replace function carebridge_set_branding(
  p_doctor uuid default null,   -- null -> set the clinic logo instead
  p_url    text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_active_role() not in ('doctor', 'admin') then
    raise exception 'branding requires a clinic session';
  end if;
  if p_doctor is null then
    update clinics set logo_url = p_url where id = current_clinic_id();
  else
    update doctors set photo_url = p_url
      where id = p_doctor and clinic_id = current_clinic_id()
        and (current_active_role() = 'admin' or id = current_active_doctor_id());
    if not found then
      raise exception 'no such doctor under your scope';
    end if;
  end if;
end;
$$;

grant execute on function carebridge_set_branding(uuid, text) to authenticated;
