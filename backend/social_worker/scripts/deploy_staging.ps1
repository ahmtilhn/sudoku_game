$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workerRoot = Split-Path -Parent $PSScriptRoot
Push-Location $workerRoot

try {
    if ([string]::IsNullOrWhiteSpace($env:CLOUDFLARE_API_TOKEN)) {
        throw "CLOUDFLARE_API_TOKEN is not set in this PowerShell session."
    }

    Write-Host "Installing Worker dependencies..." -ForegroundColor Cyan
    npm ci

    Write-Host "Running Worker typecheck..." -ForegroundColor Cyan
    npm run typecheck

    Write-Host "Running Worker tests..." -ForegroundColor Cyan
    npm test

    Write-Host "Applying pending staging D1 migrations..." -ForegroundColor Cyan
    npx wrangler d1 migrations apply sudoku-duel-social-staging `
        --remote `
        --config wrangler.staging.toml

    Write-Host "Deploying staging Worker with entry_v2..." -ForegroundColor Cyan
    npx wrangler deploy --config wrangler.staging.toml

    $baseUrl = "https://sudoku-duel-social-staging.ilhanahmet246.workers.dev"
    Write-Host "Checking staging health..." -ForegroundColor Cyan
    $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method Get
    $version = Invoke-RestMethod -Uri "$baseUrl/version" -Method Get

    if ($health.ok -ne $true) {
        throw "Staging Worker health check did not return ok=true."
    }

    Write-Host "Staging Worker is healthy." -ForegroundColor Green
    Write-Host ("Service: {0}" -f $health.service) -ForegroundColor Green
    Write-Host ("Protocol: {0}; Schema: {1}; Environment: {2}; Build: {3}" -f `
        $version.protocolVersion, `
        $version.schemaVersion, `
        $version.environment, `
        $version.buildCommit) -ForegroundColor Green
}
finally {
    Pop-Location
}
