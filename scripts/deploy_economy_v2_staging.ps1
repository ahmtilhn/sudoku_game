$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$wrangler = '.\backend\social_worker\node_modules\.bin\wrangler.cmd'
$config = '.\backend\social_worker\wrangler.staging.toml'
$generatedConfig = '.\backend\social_worker\wrangler.staging.generated.toml'

if (-not (Test-Path $wrangler)) {
    throw 'Wrangler is not installed. Run scripts\validate_economy_v2.ps1 first.'
}

$commit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
    throw 'Unable to resolve the checked-out Git commit.'
}

$configText = Get-Content $config -Raw
$configText = $configText -replace 'BUILD_COMMIT\s*=\s*"[^"]*"', "BUILD_COMMIT = `"$commit`""
Set-Content -Path $generatedConfig -Value $configText -Encoding utf8

try {
    Write-Host "`n===== Wrangler identity =====" -ForegroundColor Cyan
    & $wrangler whoami --config $generatedConfig
    if ($LASTEXITCODE -ne 0) { throw 'Wrangler authentication failed.' }

    Write-Host "`n===== Remote D1 migrations =====" -ForegroundColor Cyan
    & $wrangler d1 migrations apply sudoku-duel-social-staging --remote --config $generatedConfig
    if ($LASTEXITCODE -ne 0) {
        throw 'Remote D1 migrations failed. The Worker was not deployed.'
    }

    Write-Host "`n===== Staging Worker deployment =====" -ForegroundColor Cyan
    & $wrangler deploy --config $generatedConfig
    if ($LASTEXITCODE -ne 0) { throw 'Staging Worker deployment failed.' }

    $baseUrl = 'https://sudoku-duel-social-staging.ilhanahmet246.workers.dev'
    Write-Host "`n===== Health =====" -ForegroundColor Cyan
    Invoke-RestMethod -Uri "$baseUrl/health" -Method Get | ConvertTo-Json -Depth 10

    Write-Host "`n===== Version =====" -ForegroundColor Cyan
    $version = Invoke-RestMethod -Uri "$baseUrl/version" -Method Get
    $version | ConvertTo-Json -Depth 10
    $reportedCommit = [string]$version.commit
    if ([string]::IsNullOrWhiteSpace($reportedCommit)) {
        $reportedCommit = [string]$version.buildCommit
    }
    if (-not [string]::IsNullOrWhiteSpace($reportedCommit) -and $reportedCommit -ne $commit) {
        throw "Worker version mismatch. Expected $commit, received $reportedCommit."
    }

    Write-Host "`nStaging migration and deployment completed for $commit." -ForegroundColor Green
    Write-Host 'Run physical Android/iOS tests before any production promotion.' -ForegroundColor Yellow
} finally {
    Remove-Item $generatedConfig -Force -ErrorAction SilentlyContinue
}
