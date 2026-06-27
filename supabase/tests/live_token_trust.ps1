# CareBridge — Phase 4.5 acceptance gate: prove the LIVE token path.
#
# Re-runs Section 12 trust tests (b)/(c) + a doctor->admin scope switch against
# REAL GoTrue-issued, asymmetric-signed tokens whose scope claims are injected by
# the custom_access_token_hook from scope_sessions — NOT simulated set_config.
#
# Path exercised:  GoTrue sign-in/refresh -> hook injects claims -> asymmetric
#                  signature -> PostgREST verifies -> auth.jwt() -> RLS filters.
#
# PREREQUISITES (dashboard, done before running):
#   1. Asymmetric signing key added + set as CURRENT (legacy HS256 = standby).
#   3. custom_access_token_hook registered (Auth -> Hooks -> Customize Access Token).
#
# Reads SUPABASE_URL + SUPABASE_ANON_KEY (app/.env) and SUPABASE_SERVICE_ROLE_KEY
# + SUPABASE_DB_URL (root .env). Secrets are never printed.
#
# Run:  pwsh supabase/tests/live_token_trust.ps1   (from repo root)

$ErrorActionPreference = "Stop"
$root  = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent  # repo root
function Get-EnvVal($file, $key) {
  (Get-Content (Join-Path $root $file) | Where-Object { $_ -match "^$key=" }) `
    -replace "^$key=", "" | ForEach-Object { $_.Trim().Trim('"') } | Select-Object -First 1
}

# NOTE: app/.env's SUPABASE_URL includes a /rest/v1/ suffix, so derive the bare
# project URL — we build /auth/v1 and /rest/v1 paths off this base ourselves.
$URL     = [regex]::Match((Get-EnvVal "app/.env" "SUPABASE_URL"), '^https://[a-z0-9]+\.supabase\.co').Value
$ANON    = Get-EnvVal "app/.env"  "SUPABASE_ANON_KEY"
$SERVICE = Get-EnvVal ".env"      "SUPABASE_SERVICE_ROLE_KEY"
$DBURL   = Get-EnvVal ".env"      "SUPABASE_DB_URL"
$CLI     = "$env:LOCALAPPDATA\supabase-cli\supabase.exe"

if (-not $URL -or -not $ANON -or -not $SERVICE -or -not $DBURL) {
  throw "Missing one of SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_DB_URL"
}

# Stable test UUIDs (mirror rls_trust.sql scenario).
$ca = "aaaaaaaa-0000-0000-0000-0000000000a5"   # clinic A (distinct from other tests)
$d1 = "d1111111-0000-0000-0000-0000000000a5"
$d2 = "d2222222-0000-0000-0000-0000000000a5"
$p1 = "a1111111-0000-0000-0000-0000000000a5"   # granted to D1
$p2 = "a2222222-0000-0000-0000-0000000000a5"   # granted to D2
$email = "clinic.livetest@carebridge.internal"
$pass  = "LiveTest-" + [guid]::NewGuid().ToString("N").Substring(0,16) + "!aA1"

$adminHdr = @{ apikey = $SERVICE; Authorization = "Bearer $SERVICE"; "Content-Type" = "application/json" }
$anonHdr  = @{ apikey = $ANON;    "Content-Type" = "application/json" }

function Invoke-Sql($sql) {
  $tmp = New-TemporaryFile
  Set-Content -Path $tmp -Value $sql -Encoding utf8
  # The CLI prints "Connecting..." to stderr; don't let that count as a failure.
  # Only a non-zero exit code is a real error.
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & $CLI db query --file $tmp --db-url $DBURL 2>&1
    if ($LASTEXITCODE -ne 0) { throw "db query failed: $($out -join "`n")" }
  } finally {
    $ErrorActionPreference = $prev
    Remove-Item $tmp -Force
  }
}

function Claims($jwt) {
  $p = $jwt.Split(".")[1].Replace("-", "+").Replace("_", "/")
  switch ($p.Length % 4) { 2 { $p += "==" } 3 { $p += "=" } }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
}

function Sign-In($em, $pw) {
  Invoke-RestMethod -Method Post -Uri "$URL/auth/v1/token?grant_type=password" `
    -Headers $anonHdr -Body (@{ email = $em; password = $pw } | ConvertTo-Json)
}
function Refresh($rt) {
  Invoke-RestMethod -Method Post -Uri "$URL/auth/v1/token?grant_type=refresh_token" `
    -Headers $anonHdr -Body (@{ refresh_token = $rt } | ConvertTo-Json)
}
function Visible-Patient($token, $patientId) {
  $r = Invoke-RestMethod -Method Get -Uri "$URL/rest/v1/patients?id=eq.$patientId&select=id" `
    -Headers @{ apikey = $ANON; Authorization = "Bearer $token" }
  return ($r | Measure-Object).Count -ge 1
}
function Set-Scope($uid, $role, $docId) {
  $doc = if ($docId) { "'$docId'" } else { "null" }
  Invoke-Sql @"
insert into scope_sessions (auth_uid, clinic_id, active_role, active_doctor_id)
values ('$uid','$ca','$role',$doc)
on conflict (auth_uid) do update
  set active_role='$role', active_doctor_id=$doc, clinic_id='$ca', updated_at=now();
"@
}

$authUid = $null
$failures = @()
try {
  Write-Host "Provisioning GoTrue user + seed..."
  $u = Invoke-RestMethod -Method Post -Uri "$URL/auth/v1/admin/users" -Headers $adminHdr `
    -Body (@{ email = $email; password = $pass; email_confirm = $true } | ConvertTo-Json)
  $authUid = $u.id

  Invoke-Sql @"
do `$`$
begin
  insert into clinics (id, name, registration_number, auth_user_id)
    values ('$ca','Live Clinic','REG-LIVE-A5','$authUid');
  insert into doctors (id, clinic_id, name, council_reg_number, council_name, specialty) values
    ('$d1','$ca','Dr One','MC-A5-1','NMC','GP'),
    ('$d2','$ca','Dr Two','MC-A5-2','NMC','Cardio');
  insert into patients (id, name, phone) values
    ('$p1','Live P1','+91900000a501'),
    ('$p2','Live P2','+91900000a502');
  insert into access_grants (patient_id, granted_to_type, granted_to_id, type, status) values
    ('$p1','doctor','$d1','standing','active'),
    ('$p2','doctor','$d2','standing','active');
end `$`$;
"@

  # ---- TEST (b): doctor-scoped D1 sees only its own patient ----
  Set-Scope $authUid "doctor" $d1
  $s = Sign-In $email $pass            # fresh token issued AFTER scope set
  $c = Claims $s.access_token
  if ($c.clinic_id -ne $ca)        { $failures += "(b) token missing clinic_id claim (hook not firing?)" }
  if ($c.active_role -ne "doctor") { $failures += "(b) token missing active_role=doctor claim" }
  if (-not (Visible-Patient $s.access_token $p1)) { $failures += "(b) D1 should see its own patient P1" }
  if (Visible-Patient $s.access_token $p2)        { $failures += "(b) D1 must NOT see D2's patient P2" }
  if ($failures.Count -eq 0) { Write-Host "TEST (b) PASS: live doctor token sees only P1 (claims via auth.jwt())." }

  # ---- TEST (c): admin-scoped inherits via ANY clinic doctor (AC-8), via REFRESH ----
  Set-Scope $authUid "admin" $null
  $r = Refresh $s.refresh_token        # refresh pulls the NEW (admin) claims
  $c2 = Claims $r.access_token
  if ($c2.active_role -ne "admin") { $failures += "(c) refreshed token missing active_role=admin (switch not reflected)" }
  if (-not (Visible-Patient $r.access_token $p1)) { $failures += "(c) admin should inherit P1 (D1 grant)" }
  if (-not (Visible-Patient $r.access_token $p2)) { $failures += "(c) admin should inherit P2 (D2 grant)" }
  if ($failures.Count -eq 0) { Write-Host "TEST (c) PASS: live admin token inherits P1+P2 across clinic doctors." }

  # ---- SWITCH: admin -> doctor again, prove the earlier admin token can't linger ----
  Set-Scope $authUid "doctor" $d1
  $r2 = Refresh $r.refresh_token
  $c3 = Claims $r2.access_token
  if ($c3.active_role -ne "doctor")                { $failures += "(switch) token did not revert to doctor scope" }
  if (Visible-Patient $r2.access_token $p2)         { $failures += "(switch) doctor scope must NOT see P2 after switch" }
  if ($failures.Count -eq 0) { Write-Host "SWITCH PASS: doctor<->admin scope switch reflected in fresh tokens." }
}
finally {
  Write-Host "Cleanup..."
  # Single command (DO block): db query rejects multiple semicolon-separated statements.
  Invoke-Sql @"
do `$`$
begin
  delete from scope_sessions where auth_uid = '$authUid';
  delete from access_grants where granted_to_id in ('$d1','$d2');
  delete from patients where id in ('$p1','$p2');
  delete from doctors  where id in ('$d1','$d2');
  delete from clinics  where id = '$ca';
end `$`$;
"@
  if ($authUid) {
    try { Invoke-RestMethod -Method Delete -Uri "$URL/auth/v1/admin/users/$authUid" -Headers $adminHdr | Out-Null } catch {}
  }
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "LIVE_TOKEN_TRUST FAIL:" -ForegroundColor Red
  $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
} else {
  Write-Host ""
  Write-Host "LIVE_TOKEN_TRUST_OK :: (b) doctor isolation PASS :: (c) admin inherited-visibility PASS :: switch PASS" -ForegroundColor Green
}
