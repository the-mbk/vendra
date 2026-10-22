# ══════════════════════════════════════════════════════════════
# Vendra — run everything locally (Windows PowerShell)
#
#   .\run-local.ps1            database + backend + admin + the three apps
#   .\run-local.ps1 -NoApps    database + backend + admin only
#   .\run-local.ps1 -Reset     wipe the database, stored files and payment gateway, then reload the demo data
#   .\run-local.ps1 -Production  run the backend with APP_MODE=production (no test-card hints,
#                               manual GPS, fast timers or demo logins; demo data is not loaded)
#
# Each service opens in its own window; close a window to stop that service.
# The database and file storage keep running in Docker: stop them with
#   docker compose -f backend\docker-compose.yml down
#
# Docker also runs:
#   SeaweedFS   S3-compatible file storage standing in for Cloudflare R2 — http://localhost:8888/buckets/
#   Vendra Pay  the card payment gateway sandbox — dashboard and test cards at http://localhost:4242
# ══════════════════════════════════════════════════════════════

param(
    [switch]$NoApps,
    [switch]$Reset,
    [switch]$Production
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$backend = Join-Path $root 'backend'
$dbUrl = 'postgresql://postgres:vendra_dev@localhost:5433/vendra_db'
# Matches backend\docker-compose.yml and backend\docker\seaweedfs-s3.json
$storageEnv = "`$env:S3_ENDPOINT='http://localhost:8333'; `$env:S3_REGION='us-east-1'; `$env:S3_BUCKET='vendra-files'; " +
              "`$env:S3_ACCESS_KEY_ID='vendra'; `$env:S3_SECRET_ACCESS_KEY='vendra_dev_secret'"
# Matches the gateway service in backend\docker-compose.yml
$gatewayEnv = "`$env:GATEWAY_URL='http://localhost:4242'; `$env:GATEWAY_PUBLISHABLE_KEY='pk_test_vendra'; " +
              "`$env:GATEWAY_SECRET_KEY='sk_test_vendra'; `$env:GATEWAY_WEBHOOK_SECRET='whsec_vendra'"
$mode = if ($Production) { 'production' } else { 'development' }
$modeEnv = "`$env:APP_MODE='$mode'"
if ($Production) {
    # Production mode refuses development secrets and needs the allowed origins spelled out.
    # A fresh secret each run: everyone signs in again after a restart.
    $secret = -join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $origins = 'http://localhost:3001,http://localhost:5001,http://localhost:5002,http://localhost:5003'
    $modeEnv += "; `$env:JWT_SECRET='$secret'; `$env:ALLOWED_ORIGINS='$origins'"
}

$flutter = 'C:\fltr\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

function Step($msg) { Write-Host "`n▶ $msg" -ForegroundColor Cyan }

# ── 1. Docker ─────────────────────────────────────────────────
Step 'Checking Docker'
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    $dockerDesktop = Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'
    if (-not (Test-Path $dockerDesktop)) { $dockerDesktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe' }
    Write-Host 'Starting Docker Desktop…'
    Start-Process $dockerDesktop
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        docker info *> $null
        if ($LASTEXITCODE -eq 0) { break }
    }
    if ($LASTEXITCODE -ne 0) { throw 'Docker did not start. Open Docker Desktop and run this script again.' }
}

# ── 2. Database ───────────────────────────────────────────────
Push-Location $backend
try {
    if ($Reset) {
        Step 'Wiping the local database'
        docker compose down -v
    }
    Step 'Starting Postgres (vendra-db), file storage (vendra-storage) and the payment gateway (vendra-pay)'
    docker compose up -d --build --wait
    if ($LASTEXITCODE -ne 0) { throw 'Docker services failed to start (is something else using port 5433, 8333, 8888 or 4242?).' }

    if (-not (Test-Path (Join-Path $backend 'node_modules'))) {
        Step 'Installing backend packages'
        npm install --no-audit --no-fund
    }

    Step 'Applying migrations'
    $env:DATABASE_URL = $dbUrl
    node src/migrate.js
    if ($LASTEXITCODE -ne 0) { throw 'Migrations failed.' }

    # Loads demo data only into an empty database (the seed script refuses otherwise)
    if ($Production) {
        Write-Host 'Production mode: demo data is not loaded.'
    } else {
        # ~1,000 users, ~2,000 products and 90 days of orders in Islamabad and Rawalpindi.
        # The first run downloads the product catalogue and photos (cached in backend\.cache).
        $env:APP_MODE = 'development'
        $out = cmd /c "node src/seed.js 2>&1"
        if ($LASTEXITCODE -eq 0) { $out | ForEach-Object { Write-Host $_ } }
        elseif ("$out" -match 'already has users') { Write-Host 'Existing data kept.' }
        else { $out | ForEach-Object { Write-Host $_ }; Write-Warning 'Demo data was not loaded (see above).' }
    }
}
finally {
    Pop-Location
}

# ── 3. Services, each in its own window ───────────────────────
function Start-Window($title, $dir, $command) {
    $full = "`$host.UI.RawUI.WindowTitle = '$title'; Set-Location '$dir'; $command"
    Start-Process powershell -ArgumentList '-NoExit', '-Command', $full | Out-Null
}

Step "Starting backend on http://localhost:3000 ($mode mode)"
Start-Window "Vendra backend ($mode)" $backend "`$env:DATABASE_URL='$dbUrl'; $storageEnv; $gatewayEnv; $modeEnv; npm run dev"

Step 'Starting admin dashboard on http://localhost:3001'
$admin = Join-Path $root 'frontend-admin'
if (-not (Test-Path (Join-Path $admin 'node_modules'))) {
    Push-Location $admin; npm install --no-audit --no-fund; Pop-Location
}
Start-Window 'Vendra admin' $admin 'npm run dev -- -p 3001'

if (-not $NoApps) {
    # flutter run -d chrome opens each app in its own Chrome window (separate logins),
    # with hot reload: press r in the window after editing code.
    $apps = @(
        @{ Name = 'customer'; Port = 5001 },
        @{ Name = 'vendor';   Port = 5002 },
        @{ Name = 'rider';    Port = 5003 }
    )
    foreach ($a in $apps) {
        Step "Starting $($a.Name) app on http://localhost:$($a.Port)"
        $dir = Join-Path $root "frontend-$($a.Name)"
        Start-Window "Vendra $($a.Name)" $dir "& '$flutter' run -d chrome --web-port $($a.Port)"
    }
}

Write-Host "`n✓ Started in $mode mode." -ForegroundColor Green
Write-Host '  Admin dashboard                  http://localhost:3001'
Write-Host '  Customer / vendor / rider apps   http://localhost:5001 / 5002 / 5003'
Write-Host '  Vendra Pay dashboard             http://localhost:4242  (test cards listed there)'
Write-Host '  Stored files                     http://localhost:8888/buckets/'
if (-not $Production) { Write-Host '  Demo logins are listed on each login screen (password123).' }
