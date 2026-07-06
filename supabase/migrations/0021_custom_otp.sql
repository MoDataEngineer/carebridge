-- CareBridge — Phase 11 (D12): custom OTP, Supabase-hosted.
--
-- Founder decision 2026-07-06: Firebase Phone Auth is too costly per SMS for
-- Indian volumes — OTP codes are generated/stored/verified HERE, and only the
-- SMS send is provider-specific (MSG91 first; swappable via secrets, same
-- pattern as the Groq/Claude AI provider). Also removes Firebase's
-- authorized-domain restriction, so OTP works from any host (LAN testing).
--
-- Table is SERVICE-ONLY: codes are written/verified exclusively by the
-- mint-scope-token Edge Function (hashed, 5-min expiry, 5 attempts, single
-- use). Clients never touch it.

create table if not exists auth_otps (
  phone      text primary key,          -- normalized last-10 digits
  code_hash  text not null,             -- sha-256 of the 6-digit code
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  attempts   int not null default 0,
  consumed   boolean not null default false
);

alter table auth_otps enable row level security;
revoke all on auth_otps from public, anon, authenticated;
-- No policies: only service_role (RLS-exempt) may use it.
