$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Host "`n===== $Name =====" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

Invoke-Step 'Flutter packages' {
    flutter pub get
}

Invoke-Step 'Dart format' {
    dart format lib test
}

Invoke-Step 'Whitespace validation' {
    git diff --check
}

Invoke-Step 'Flutter static analysis' {
    flutter analyze
}

Invoke-Step 'Flutter tests' {
    flutter test
}

Invoke-Step 'Worker packages' {
    if (-not (Test-Path 'backend/social_worker/node_modules')) {
        npm --prefix backend/social_worker ci
    } else {
        npm --prefix backend/social_worker install --ignore-scripts
    }
}

Invoke-Step 'Worker typecheck' {
    npm --prefix backend/social_worker run typecheck
}

Invoke-Step 'Worker tests' {
    npm --prefix backend/social_worker test
}

Invoke-Step 'Local D1 migrations' {
    .\backend\social_worker\node_modules\.bin\wrangler.cmd d1 migrations apply sudoku-duel-social-staging --local --config .\backend\social_worker\wrangler.staging.toml
}

Write-Host "`nAll local validation steps passed." -ForegroundColor Green
Write-Host 'The formatter may have changed tracked Dart files. Review and commit those formatting changes before deployment.' -ForegroundColor Yellow
Write-Host 'Remote D1 migrations, staging deployment, store sandbox products and physical-device tests are still separate release gates.' -ForegroundColor Yellow
