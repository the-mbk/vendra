# ══════════════════════════════════════════════════════════════
# Vendra — run everything locally (Windows PowerShell)
#
#   .\run-local.ps1            database + backend + admin + the three apps
#   .\run-local.ps1 -NoApps    database + backend + admin only
#   .\run-local.ps1 -Reset     wipe the local database and reload the demo data first
#
# Each service opens in its own window; close a window to stop that service.
# The database keeps running in Docker: stop it with
#   docker compose -f backend\docker-compose.yml down
# ══════════════════════════════════════════════════════════════

param(
    [switch]$NoApps,
    [switch]$Reset
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$backend = Join-Path $root 'backend'
$dbUrl = 'postgresql://postgres:vendra_dev@localhost:5433/vendra_db'

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
    Step 'Starting Postgres (vendra-db)'
    docker compose up -d --wait
    if ($LASTEXITCODE -ne 0) { throw 'Postgres failed to start (is something else using port 5433?).' }

    if (-not (Test-Path (Join-Path $backend 'node_modules'))) {
        Step 'Installing backend packages'
        npm install --no-audit --no-fund
    }

    Step 'Applying migrations'
    $env:DATABASE_URL = $dbUrl
    node src/migrate.js
    if ($LASTEXITCODE -ne 0) { throw 'Migrations failed.' }

    # Loads demo data only into an empty database (the seed script refuses otherwise)
    node src/seed.js 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host 'Demo data loaded (all accounts use password123).' }
    else { Write-Host 'Existing data kept.' }
}
finally {
    Pop-Location
}

# ── 3. Services, each in its own window ───────────────────────
function Start-Window($title, $dir, $command) {
    $full = "`$host.UI.RawUI.WindowTitle = '$title'; Set-Location '$dir'; $command"
    Start-Process powershell -ArgumentList '-NoExit', '-Command', $full | Out-Null
}

Step 'Starting backend on http://localhost:3000'
Start-Window 'Vendra backend' $backend "`$env:DATABASE_URL='$dbUrl'; npm run dev"

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

Write-Host "`n✓ Started. Logins are in backend\README.md (password123 for every demo account)." -ForegroundColor Green
