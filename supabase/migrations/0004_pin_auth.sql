-- CareBridge — Phase 2 D1 PIN auth (hashed, rate-limited).
-- PINs are hashed with pgcrypto bcrypt; never stored or compared in plaintext.
-- These functions are SERVER-ONLY: the mint-scope-token Edge Function calls them
-- with the service role. Execute is revoked from anon/authenticated so a client
-- can never brute-force PINs directly against the API.

-- Failed-attempt tracking for lockout (D1: rate-limited).
create table if not exists auth_pin_attempts (
  identity_type text not null check (identity_type in ('doctor','admin')),
  identity_id   uuid not null,                 -- doctor.id, or clinic.id for admin
  failed_count  int  not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now(),
  primary key (identity_type, identity_id)
);
alter table auth_pin_attempts enable row level security;  -- no policies: clients can't touch it

-- Set/replace a PIN (hashed). Called when a solo clinic sets its PIN at first
-- login, or when an admin sets/resets a doctor's or the admin PIN.
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
  else
    raise exception 'unknown identity type %', p_type;
  end if;
  delete from auth_pin_attempts where identity_type = p_type and identity_id = p_id;
end $$;

-- Verify a PIN with lockout. Returns {ok, reason, locked_until}.
-- 5 consecutive failures -> 15-minute lock.
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

  -- record failure
  insert into auth_pin_attempts as a (identity_type, identity_id, failed_count, updated_at)
    values (p_type, p_id, 1, now())
  on conflict (identity_type, identity_id) do update
    set failed_count = a.failed_count + 1,
        updated_at   = now(),
        locked_until = case when a.failed_count + 1 >= 5 then now() + interval '15 minutes' else a.locked_until end;

  return jsonb_build_object('ok', false, 'reason', 'bad_pin');
end $$;

-- Lock these down: clients (anon/authenticated) must never call them.
revoke all on function carebridge_set_pin(text, uuid, text)    from public, anon, authenticated;
revoke all on function carebridge_verify_pin(text, uuid, text) from public, anon, authenticated;
grant execute on function carebridge_set_pin(text, uuid, text)    to service_role;
grant execute on function carebridge_verify_pin(text, uuid, text) to service_role;
