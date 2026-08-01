$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$workerDir = Join-Path $root 'backend\social_worker'
$workerConfig = Join-Path $workerDir 'wrangler.staging.toml'
$workerDatabase = 'sudoku-duel-social-staging'

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Host "`n===== $Name =====" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

function Resolve-Cmd {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$MissingMessage,
        [switch]$PreferCmd
    )

    $commands = @(Get-Command $Name -ErrorAction SilentlyContinue)
    if ($PreferCmd) {
        $cmd = $commands |
            Where-Object { $_.Source -and $_.Source.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if ($cmd) {
            return $cmd.Source
        }
    }

    $command = $commands | Select-Object -First 1
    if (-not $command) {
        throw $MissingMessage
    }

    return $command.Source
}

function Resolve-Wrangler {
    $localWrangler = Join-Path $workerDir 'node_modules\.bin\wrangler.cmd'
    if (Test-Path -LiteralPath $localWrangler) {
        return @{
            Command = $localWrangler
            Args = @()
            Description = $localWrangler
        }
    }

    $npx = Resolve-Cmd -Name 'npx.cmd' -MissingMessage 'Wrangler bulunamadı: backend/social_worker/node_modules/.bin/wrangler.cmd yok ve npx.cmd bulunamadı.' -PreferCmd
    return @{
        Command = $npx
        Args = @('wrangler')
        Description = "$npx wrangler"
    }
}

$node = Resolve-Cmd -Name 'node.exe' -MissingMessage 'Node bulunamadı. Node.js kurulumunu PATH içine ekleyin.' -PreferCmd
$npm = Resolve-Cmd -Name 'npm.cmd' -MissingMessage 'npm bulunamadı. Node.js npm.cmd kurulumunu PATH içine ekleyin.' -PreferCmd

if (-not (Test-Path -LiteralPath (Join-Path $workerDir 'package.json'))) {
    throw 'package.json bulunamadı: backend/social_worker/package.json'
}

if (-not (Test-Path -LiteralPath (Join-Path $workerDir 'package-lock.json'))) {
    throw 'package-lock.json bulunamadı: tekrarlanabilir kurulum için npm ci gerekli. Lock dosyasını bilinçli olarak oluşturup commit kapsamına alın.'
}

Write-Host "Node: $node" -ForegroundColor DarkGray
Write-Host "npm: $npm" -ForegroundColor DarkGray

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
    flutter test --reporter expanded --concurrency=1 --timeout 60s
}

Invoke-Step 'Worker packages' {
    & $npm --prefix $workerDir ci
}

Invoke-Step 'Worker typecheck' {
    & $npm --prefix $workerDir run typecheck
}

Invoke-Step 'Worker tests' {
    & $npm --prefix $workerDir test
}

Invoke-Step 'Local D1 migrations' {
    if (-not (Test-Path -LiteralPath $workerConfig)) {
        throw "Wrangler config bulunamadı: $workerConfig"
    }

    $wrangler = Resolve-Wrangler
    Write-Host "Wrangler: $($wrangler.Description)" -ForegroundColor DarkGray
    Write-Host "D1 database: $workerDatabase" -ForegroundColor DarkGray
    Write-Host "Config: $workerConfig" -ForegroundColor DarkGray
    $wranglerCommand = $wrangler.Command
    $wranglerArgs = @($wrangler.Args) + @('d1', 'migrations', 'apply', $workerDatabase, '--local', '--config', $workerConfig)
    & $wranglerCommand @wranglerArgs
}

Write-Host "`nAll local validation steps passed." -ForegroundColor Green
Write-Host 'The formatter may have changed tracked Dart files. Review and commit those formatting changes before deployment.' -ForegroundColor Yellow
Write-Host 'Manual release gates still required: remote D1 migrations, staging deployment, Worker secrets, store sandbox products, Firebase/App Check console setup and physical-device tests.' -ForegroundColor Yellow
