[CmdletBinding()]
param(
    [string]$ConfigPath = 'backend/social_worker/wrangler.toml',
    [switch]$AllowPlaceholders,
    [string]$BackendUrl = $env:SOCIAL_BACKEND_URL,
    [string]$BuildCommit = $env:BUILD_COMMIT
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$Message) { $errors.Add($Message) }
function Add-Warning([string]$Message) { $warnings.Add($Message) }

function Get-TomlString {
    param([string]$Content, [string]$Key)
    $pattern = '(?m)^\s*{0}\s*=\s*"([^"]*)"\s*$' -f [regex]::Escape($Key)
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Assert-ExactValue {
    param([string]$Content, [string]$Key, [string]$Expected)
    $actual = Get-TomlString $Content $Key
    if ($null -eq $actual) {
        Add-Error "Missing required Worker variable: $Key"
    } elseif ($actual -ne $Expected) {
        Add-Error "$Key must be '$Expected' but is '$actual'."
    }
}

function Assert-ConfiguredValue {
    param([string]$Content, [string]$Key)
    $actual = Get-TomlString $Content $Key
    if ([string]::IsNullOrWhiteSpace($actual)) {
        Add-Error "Missing required Worker variable: $Key"
        return
    }
    if (-not $AllowPlaceholders -and ($actual -match 'REPLACE_|^local$|^example$')) {
        Add-Error "$Key still contains a placeholder value."
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Production Worker config was not found: $ConfigPath"
}

$content = Get-Content -LiteralPath $ConfigPath -Raw
Assert-ExactValue $content 'ENVIRONMENT' 'production'
Assert-ExactValue $content 'REQUIRE_APP_CHECK' 'true'
Assert-ExactValue $content 'ALLOW_TEST_PURCHASE_GRANTS' 'false'
Assert-ExactValue $content 'DEBUG_UNLIMITED_COINS' 'false'
Assert-ConfiguredValue $content 'FIREBASE_PROJECT_ID'
Assert-ConfiguredValue $content 'FIREBASE_PROJECT_NUMBER'
Assert-ConfiguredValue $content 'ALLOWED_APP_CHECK_APP_IDS'
Assert-ConfiguredValue $content 'GOOGLE_PLAY_PACKAGE_NAME'
Assert-ConfiguredValue $content 'GOOGLE_PUBSUB_AUDIENCE'
Assert-ConfiguredValue $content 'GOOGLE_PUBSUB_SERVICE_ACCOUNT'
Assert-ConfiguredValue $content 'APPLE_BUNDLE_ID'
Assert-ConfiguredValue $content 'BUILD_COMMIT'

if ($content -notmatch '(?m)^\s*binding\s*=\s*"DB"\s*$') {
    Add-Error 'Production D1 binding DB is missing.'
}
if ($content -notmatch '(?m)^\s*name\s*=\s*"GAME_ROOMS"\s*$') {
    Add-Error 'Production Durable Object binding GAME_ROOMS is missing.'
}
if ($content -notmatch '(?m)^\s*name\s*=\s*"MATCHMAKING_QUEUE"\s*$') {
    Add-Error 'Production Durable Object binding MATCHMAKING_QUEUE is missing.'
}
if (-not $AllowPlaceholders -and $content -match 'REPLACE_WITH_D1_DATABASE_ID') {
    Add-Error 'Production D1 database ID is still a placeholder.'
}
if ($content -match 'ENVIRONMENT\s*=\s*"staging"') {
    Add-Error 'A staging environment value is present in the production config.'
}

if (-not [string]::IsNullOrWhiteSpace($BackendUrl)) {
    $uri = $null
    try { $uri = [System.Uri]$BackendUrl } catch { Add-Error 'SOCIAL_BACKEND_URL is not a valid URL.' }
    if ($null -ne $uri) {
        if ($uri.Scheme -ne 'https') { Add-Error 'SOCIAL_BACKEND_URL must use HTTPS.' }
        if ([string]::IsNullOrWhiteSpace($uri.Host)) { Add-Error 'SOCIAL_BACKEND_URL must have a host.' }
        if ($uri.Host -match 'staging|localhost|127\.0\.0\.1') {
            Add-Error 'SOCIAL_BACKEND_URL points to staging or a local host.'
        }
    }
} elseif (-not $AllowPlaceholders) {
    Add-Error 'SOCIAL_BACKEND_URL is required for a production release.'
}

if (-not [string]::IsNullOrWhiteSpace($BuildCommit)) {
    if ($BuildCommit -notmatch '^[0-9a-fA-F]{7,40}$') {
        Add-Error 'BUILD_COMMIT must be a 7-40 character Git commit SHA.'
    }
} elseif (-not $AllowPlaceholders) {
    Add-Error 'BUILD_COMMIT is required for a production release.'
}

$requiredSecrets = @(
    'FCM_CLIENT_EMAIL',
    'FCM_PRIVATE_KEY',
    'GOOGLE_PLAY_CLIENT_EMAIL',
    'GOOGLE_PLAY_PRIVATE_KEY',
    'APPLE_IAP_ISSUER_ID',
    'APPLE_IAP_KEY_ID',
    'APPLE_IAP_PRIVATE_KEY',
    'APPLE_ROOT_CERTIFICATES_PEM'
)
if (-not $AllowPlaceholders) {
    foreach ($secret in $requiredSecrets) {
        $value = [Environment]::GetEnvironmentVariable($secret)
        if ([string]::IsNullOrWhiteSpace($value)) {
            Add-Error "Required production secret is unavailable in this environment: $secret"
        }
    }
}

foreach ($warning in $warnings) {
    Write-Warning $warning
}
if ($errors.Count -gt 0) {
    Write-Host "Production invariant check failed:" -ForegroundColor Red
    foreach ($message in $errors) {
        Write-Host " - $message" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Production invariants passed for $ConfigPath" -ForegroundColor Green
