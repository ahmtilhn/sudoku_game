[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackendUrl,
    [Parameter(Mandatory = $true)]
    [string]$BuildCommit
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$workerRoot = Join-Path $root 'backend/social_worker'
$configPath = Join-Path $workerRoot 'wrangler.production.toml'

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Command,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$FailureMessage Exit code: $LASTEXITCODE" }
}

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Production Worker config bulunamadı: $configPath"
}
if ($BuildCommit -notmatch '^[0-9a-fA-F]{7,40}$') {
    throw 'BuildCommit geçerli bir Git SHA olmalı.'
}

$uri = [Uri]$BackendUrl
if ($uri.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($uri.Host) -or
    $uri.Host -match 'staging|localhost|127\.0\.0\.1' -or
    $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
    throw 'BackendUrl gerçek production HTTPS endpointi olmalı.'
}

$config = Get-Content -LiteralPath $configPath -Raw
foreach ($required in @(
        'ENVIRONMENT = "production"',
        'REQUIRE_APP_CHECK = "true"',
        'ALLOW_TEST_PURCHASE_GRANTS = "false"',
        'DEBUG_UNLIMITED_COINS = "false"')) {
    if ($config -notmatch [Regex]::Escape($required)) {
        throw "Production config güvenlik kapısı başarısız: $required"
    }
}
if ($config -match 'sudoku-duel-social-staging|ENVIRONMENT = "staging"') {
    throw 'Production config staging değerleri içeriyor.'
}

$env:SOCIAL_BACKEND_URL = $BackendUrl.TrimEnd('/')
$env:BUILD_COMMIT = $BuildCommit

Push-Location $workerRoot
try {
    Invoke-NativeChecked { npm run typecheck } 'Worker typecheck başarısız.'
    Invoke-NativeChecked { npm test } 'Worker testleri başarısız.'
    Invoke-NativeChecked { npm run puzzles:verify } 'Ranked puzzle doğrulaması başarısız.'
    Invoke-NativeChecked { npx wrangler deploy --config wrangler.production.toml --dry-run } 'Production Worker dry-run başarısız.'

    Invoke-NativeChecked {
        npx wrangler d1 migrations list sudoku-duel-social-production --remote --config wrangler.production.toml
    } 'Production D1 migration listesi alınamadı.'
} finally {
    Pop-Location
}

$health = Invoke-RestMethod -Uri "$($env:SOCIAL_BACKEND_URL)/health" -Method Get
$version = Invoke-RestMethod -Uri "$($env:SOCIAL_BACKEND_URL)/version" -Method Get
if ($health.ok -ne $true) { throw 'Production Worker health kontrolü başarısız.' }
if ($version.environment -ne 'production') { throw 'Canlı Worker production ortamı bildirmiyor.' }
if ($version.buildCommit -ne $BuildCommit) {
    throw "Canlı Worker commit uyuşmuyor: beklenen $BuildCommit, gelen $($version.buildCommit)."
}

foreach ($name in @('PLAYER_A_ID_TOKEN', 'PLAYER_B_ID_TOKEN')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Canlı smoke testi için $name ortam değişkeni gerekli. Token değerlerini loglama."
    }
}

Push-Location $workerRoot
try {
    Invoke-NativeChecked { npm run smoke:ranked } 'Production ranked WebSocket smoke testi başarısız.'
} finally {
    Pop-Location
}

Write-Host 'Production promotion gate başarılı: config, Worker, D1, health/version ve ranked WebSocket smoke doğrulandı.' -ForegroundColor Green