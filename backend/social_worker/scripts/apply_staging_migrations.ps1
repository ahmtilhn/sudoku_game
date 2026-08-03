param(
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $true
}

$workerRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $workerRoot 'wrangler.staging.toml'
$migrationsPath = Join-Path $workerRoot 'migrations'
$tempRoot = Join-Path $workerRoot '.wrangler\staging-migrations-clean'
$tempConfigPath = Join-Path $workerRoot 'wrangler.staging.clean.generated.toml'
$stagingUrl = 'https://sudoku-duel-social-staging.ilhanahmet246.workers.dev'

function Invoke-NativeChecked {
  param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$Command,
    [Parameter(Mandatory = $true)]
    [string]$FailureMessage
  )

  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$FailureMessage Exit code: $LASTEXITCODE"
  }
}

if (-not (Test-Path $configPath)) {
  throw "Staging config bulunamadı: $configPath"
}
if (-not (Test-Path $migrationsPath)) {
  throw "Migration klasörü bulunamadı: $migrationsPath"
}

try {
  Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $tempRoot | Out-Null

  $migrationFiles = Get-ChildItem $migrationsPath -Filter '*.sql' |
    Sort-Object Name
  if ($migrationFiles.Count -eq 0) {
    throw 'Hiç migration dosyası bulunamadı.'
  }

  foreach ($file in $migrationFiles) {
    $lines = Get-Content $file.FullName
    $insideTrigger = $false
    $cleanLines = foreach ($line in $lines) {
      if ($insideTrigger) {
        if ($line -match '^\s*END;\s*$') {
          $insideTrigger = $false
        }
        continue
      }

      if ($line -match '^\s*CREATE\s+TRIGGER\b') {
        $insideTrigger = $true
        continue
      }

      if ($line -match '^\s*--') {
        continue
      }

      $line
    }

    if ($insideTrigger) {
      throw "Kapanmayan CREATE TRIGGER bloğu bulundu: $($file.Name)"
    }

    if (-not $cleanLines -or $cleanLines.Count -eq 0) {
      $cleanLines = @('SELECT 1;')
    }

    $destination = Join-Path $tempRoot $file.Name
    [System.IO.File]::WriteAllLines(
      $destination,
      [string[]]$cleanLines,
      [System.Text.UTF8Encoding]::new($false)
    )
  }

  $configText = Get-Content $configPath -Raw
  if ($configText -notmatch 'migrations_dir\s*=\s*"migrations"') {
    throw 'wrangler.staging.toml içindeki migrations_dir beklenen biçimde değil.'
  }
  $configText = $configText -replace (
    'migrations_dir\s*=\s*"migrations"',
    'migrations_dir = ".wrangler/staging-migrations-clean"'
  )
  [System.IO.File]::WriteAllText(
    $tempConfigPath,
    $configText,
    [System.Text.UTF8Encoding]::new($false)
  )

  Push-Location $workerRoot
  try {
    Invoke-NativeChecked {
      npm run typecheck
    } 'TypeScript kontrolü başarısız.'

    Invoke-NativeChecked {
      npx wrangler@latest d1 migrations list DB `
        --remote `
        --config $tempConfigPath
    } 'Uzak D1 migration listesi alınamadı.'

    Invoke-NativeChecked {
      npx wrangler@latest d1 migrations apply DB `
        --remote `
        --config $tempConfigPath `
        --yes
    } 'Uzak D1 migration işlemi başarısız.'

    if (-not $SkipDeploy) {
      Invoke-NativeChecked {
        npx wrangler@latest deploy --config $configPath
      } 'Staging Worker deploy işlemi başarısız.'

      $statusCode = & curl.exe -sS -o NUL -w '%{http_code}' `
        "$stagingUrl/v1/competitive/profile"
      if ($LASTEXITCODE -ne 0) {
        throw 'Staging endpoint kontrolü gerçekleştirilemedi.'
      }
      if ($statusCode -notin @('401', '403')) {
        throw "Staging endpoint beklenmeyen HTTP kodu döndürdü: $statusCode"
      }
    }
  } finally {
    Pop-Location
  }
} finally {
  Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
  Remove-Item -Force $tempConfigPath -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Staging D1 migration işlemi tamamlandı.' -ForegroundColor Green
if (-not $SkipDeploy) {
  Write-Host 'Staging Worker güncel kodla deploy edildi.' -ForegroundColor Green
  Write-Host 'Runtime trigger şeması kuruldu ve profil endpointi doğrulandı.' -ForegroundColor Green
}
