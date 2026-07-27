$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$wrangler = '.\backend\social_worker\node_modules\.bin\wrangler.cmd'
$config = '.\backend\social_worker\wrangler.staging.toml'

if (-not (Test-Path $wrangler)) {
    throw 'Wrangler is not installed. Run scripts\validate_economy_v2.ps1 first.'
}

Write-Host "`n===== Wrangler identity =====" -ForegroundColor Cyan
& $wrangler whoami --config $config
if ($LASTEXITCODE -ne 0) { throw 'Wrangler authentication failed.' }

Write-Host "`n===== Remote D1 migrations =====" -ForegroundColor Cyan
& $wrangler d1 migrations apply sudoku-duel-social-staging --remote --config $config
if ($LASTEXITCODE -ne 0) { throw 'Remote D1 migrations failed. The Worker was not deployed.' }

Write-Host "`n===== Staging Worker deployment =====" -ForegroundColor Cyan
& $wrangler deploy --config $config
if ($LASTEXITCODE -ne 0) { throw 'Staging Worker deployment failed.' }

$baseUrl = 'https://sudoku-duel-social-staging.ilhanahmet246.workers.dev'
Write-Host "`n===== Health =====" -ForegroundColor Cyan
Invoke-RestMethod -Uri "$baseUrl/health" -Method Get | ConvertTo-Json -Depth 10

Write-Host "`n===== Version =====" -ForegroundColor Cyan
Invoke-RestMethod -Uri "$baseUrl/version" -Method Get | ConvertTo-Json -Depth 10

Write-Host "`nStaging migration and deployment completed." -ForegroundColor Green
Write-Host 'Run physical Android/iOS tests before any production promotion.' -ForegroundColor Yellow
