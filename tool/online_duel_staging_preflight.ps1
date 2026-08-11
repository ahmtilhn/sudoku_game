param(
  [Parameter(Mandatory=$true)]
  [string]$BackendUrl,
  [string]$WranglerConfig = "backend/social_worker/wrangler.staging.example.toml"
)

$ErrorActionPreference = "Stop"

if ((git branch --show-current) -ne "codex-authoritative-online-duel") {
  throw "Run from codex-authoritative-online-duel."
}

$uri = [Uri]$BackendUrl
if ($uri.Scheme -ne "https" -or $uri.Query) {
  throw "BackendUrl must be HTTPS and must not include query credentials."
}

if (!(Test-Path $WranglerConfig)) {
  throw "Missing Wrangler staging config: $WranglerConfig"
}

$configText = Get-Content -LiteralPath $WranglerConfig -Raw
if ($configText -match "REPLACE_WITH") {
  Write-Warning "Staging Wrangler config still contains placeholders."
}

Write-Host "Branch: $(git branch --show-current)"
Write-Host "Git status:"
git status --short

Push-Location backend/social_worker
try {
  npm run puzzles:verify
  npm run typecheck
  npm test
} finally {
  Pop-Location
}

python tool\validate_localizations.py
python tool\validate_translation_quality.py
flutter analyze
flutter test --concurrency=1 --timeout 120s -r expanded

try {
  $health = Invoke-RestMethod -Method Get -Uri "$($uri.AbsoluteUri.TrimEnd('/'))/health" -TimeoutSec 10
  Write-Host "Health service: $($health.service)"
  $version = Invoke-RestMethod -Method Get -Uri "$($uri.AbsoluteUri.TrimEnd('/'))/version" -TimeoutSec 10
  Write-Host "Protocol: $($version.protocolVersion), schema: $($version.schemaVersion), env: $($version.environment)"
} catch {
  Write-Warning "Remote /health or /version could not be verified: $($_.Exception.Message)"
}

Write-Host "Required secrets: FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY"
Write-Host "Preflight finished without exposing secret values."
