-- Ayulekha — real diagnostic-partner login (audit gap 4, 2026-07-18).
--
-- Section 2.3 + ID-5: FLAT login, one credential per lab/imaging centre —
-- registration/license number + PIN (mirrors the clinic pattern: bcrypt PIN,
-- rate-limited verify, GoTrue user provisioned by mint-scope-token with its
-- password in Vault). RLS already resolves the caller via
-- diagnostic_partners.auth_user_id -> current_partner_id() (0011); this makes
-- the session that feeds it real instead of whatever was lying around.

alter table diagnostic_partners
  add column if not exists phone    text,
  add column if not exists pin_hash text,
  add column if not exists verified boolean not null default false;

-- One lab per phone (like clinics); nullable for pre-existing rows.
create unique index if not exists idx_diagnostic_partners_phone
  on diagnostic_partners(phone) where phone is not null;

-- Demo seed partner stays usable: verified, PIN 1234 (demo data only).
-- pgcrypto lives in the `extensions` schema on Supabase; this bare (non-function)
-- statement has no `search_path`, so crypt/gen_salt must be schema-qualified —
-- unlike the functions below, which set `search_path = public, extensions`.
update diagnostic_partners
  set verified = true,
      pin_hash = coalesce(pin_hash, extensions.crypt('1234', extensions.gen_salt('bf')))
  where registration_number = 'LAB-DEMO-1';

-- ---- PIN functions learn the 'partner' identity type ----
alter table auth_pin_attempts drop constraint if exists auth_pin_attempts_identity_type_check;
alter table auth_pin_attempts
  add constraint auth_pin_attempts_identity_type_check
  check (identity_type in ('doctor', 'admin', 'partner'));

create or replace function carebridge_set_pin(p_type text, p_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_pin is null or length(p_pin) < 4 then
    raise exception 'PIN must be at least 4 digits';
  end if;
  if p_type = 'doctor' then
    update doctors set pin_hash = crypt(p_pin, gen_salt('bf')) where id = p_id;
  elsif p_type = 'admin' then
    update clinics set admin_pin_hash = crypt(p_pin, gen_salt('bf')) where id = p_id;
  elsif p_type = 'partner' then
    update diagnostic_partners set pin_hash = crypt(p_pin, gen_salt('bf')) where id = p_id;
  else
    raise exception 'unknown identity type %', p_type;
  end if;
  delete from auth_pin_attempts where identity_type = p_type and identity_id = p_id;
end $$;

create or replace function carebridge_verify_pin(p_type text, p_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
  v_attempt auth_pin_attempts%rowtype;
  v_ok boolean;
begin
  select * into v_attempt from auth_pin_attempts
    where identity_type = p_type and identity_id = p_id;

  if found and v_attempt.locked_until is not null and v_attempt.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked', 'locked_until', v_attempt.locked_until);
  end if;

  if p_type = 'doctor' then
    select pin_hash into v_hash from doctors where id = p_id and is_active;
  elsif p_type = 'admin' then
    select admin_pin_hash into v_hash from clinics where id = p_id;
  elsif p_type = 'partner' then
    select pin_hash into v_hash from diagnostic_partners where id = p_id;
  else
    raise exception 'unknown identity type %', p_type;
  end if;

  if v_hash is null then
    return jsonb_build_object('ok', false, 'reason', 'no_pin_set');
  end if;

  v_ok := (crypt(p_pin, v_hash) = v_hash);

  if v_ok then
    delete from auth_pin_attempts where identity_type = p_type and identity_id = p_id;
    return jsonb_build_object('ok', true);
  end if;

  insert into auth_pin_attempts as a (identity_type, identity_id, failed_count, updated_at)
    values (p_type, p_id, 1, now())
  on conflict (identity_type, identity_id) do update
    set failed_count = a.failed_count + 1,
        updated_at   = now(),
        locked_until = case when a.failed_count + 1 >= 5 then now() + interval '15 minutes' else a.locked_until end;

  return jsonb_build_object('ok', false, 'reason', 'bad_pin');
end $$;

-- ---- Vault storage for the partner GoTrue password (mirrors 0008) ----
create or replace function carebridge_set_partner_secret(p_partner_id uuid, p_secret text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := 'partner_password:' || p_partner_id::text;
  v_id   uuid;
begin
  select id into v_id from vault.secrets where name = v_name;
  if v_id is null then
    perform vault.create_secret(p_secret, v_name, 'Ayulekha diagnostic-partner GoTrue login password');
  else
    perform vault.update_secret(v_id, p_secret);
  end if;
end;
$$;

create or replace function carebridge_get_partner_secret(p_partner_id uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'partner_password:' || p_partner_id::text;
$$;

revoke all on function carebridge_set_partner_secret(uuid, text) from public, anon, authenticated;
revoke all on function carebridge_get_partner_secret(uuid)       from public, anon, authenticated;
grant execute on function carebridge_set_partner_secret(uuid, text) to service_role;
grant execute on function carebridge_get_partner_secret(uuid)       to service_role;
