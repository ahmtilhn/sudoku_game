param(
  [int]$ExpectedBuildNumber = 82,
  [string]$ProductionBackendUrl = "https://sudoku-duel-social-production.ilhanahmet246.workers.dev"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
  )
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Command failed with exit code $LASTEXITCODE."
  }
}

function Read-RequiredText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (!(Test-Path -LiteralPath $Path)) {
    throw "Required file is missing: $Path"
  }
  Get-Content -LiteralPath $Path -Raw
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if (!$Text.Contains($Needle)) {
    throw "Release source guard failed: $Label is missing. Refusing to build."
  }
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $projectRoot
try {
  Write-Host "=== Sudoku Duel Android production build ==="

  Invoke-Checked git fetch origin main --prune

  $gitRoot = (git rev-parse --show-toplevel).Trim()
  if ($LASTEXITCODE -ne 0) { throw "This directory is not a Git repository." }
  if ((Resolve-Path $gitRoot).Path -ne (Resolve-Path $projectRoot).Path) {
    throw "Wrong repository root. Expected $projectRoot but Git resolved $gitRoot."
  }

  $branch = (git branch --show-current).Trim()
  if ($branch -ne "main") {
    throw "Production Android builds must be created from main. Current branch: $branch"
  }

  $head = (git rev-parse HEAD).Trim()
  $originMain = (git rev-parse origin/main).Trim()
  if ($head -ne $originMain) {
    throw "Local HEAD does not equal origin/main. Run git pull --ff-only before building. HEAD=$head origin/main=$originMain"
  }

  $dirty = @(git status --porcelain --untracked-files=all)
  if ($LASTEXITCODE -ne 0) { throw "git status failed." }
  if ($dirty.Count -gt 0) {
    Write-Host ($dirty -join [Environment]::NewLine)
    throw "Working tree is not clean. Commit/stash/remove local changes before a production build."
  }

  $pubspec = Read-RequiredText (Join-Path $projectRoot "pubspec.yaml")
  $versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([^+\r\n]+)\+(\d+)\s*$')
  if (!$versionMatch.Success) {
    throw "Could not read version/build number from pubspec.yaml."
  }
  $buildName = $versionMatch.Groups[1].Value.Trim()
  $buildNumber = [int]$versionMatch.Groups[2].Value
  if ($buildNumber -ne $ExpectedBuildNumber) {
    throw "pubspec build number is $buildNumber, expected $ExpectedBuildNumber. Refusing to build."
  }

  $settings = Read-RequiredText (Join-Path $projectRoot "lib\features\settings\ux_settings_screen.dart")
  Assert-Contains $settings "_SettingsSectionPicker(" "current Settings section UI"
  Assert-Contains $settings "context.tr('ad_privacy_choices')" "ad privacy choices in Settings"
  if ($settings.Contains("context.tr('protect_player_account')")) {
    throw "Legacy Protect Player Account UI is present in the active Settings screen."
  }

  $economy = Read-RequiredText (Join-Path $projectRoot "lib\services\economy_service.dart")
  Assert-Contains $economy "_confirmRewardAfterSsv" "daily x2 SSV confirmation retry"
  Assert-Contains $economy "reward_waiting_for_ssv" "daily x2 SSV waiting error handling"
  Assert-Contains $economy "const attempts = 8" "daily x2 SSV retry count"

  $manifest = Read-RequiredText (Join-Path $projectRoot "android\app\src\main\AndroidManifest.xml")
  Assert-Contains $manifest 'android:icon="@mipmap/ic_launcher_sudoku_duel"' "new Android launcher icon"
  Assert-Contains $manifest 'android:roundIcon="@mipmap/ic_launcher_sudoku_duel"' "new Android round launcher icon"

  foreach ($density in @("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")) {
    $icon = Join-Path $projectRoot "android\app\src\main\res\mipmap-$density\ic_launcher_sudoku_duel.png"
    if (!(Test-Path -LiteralPath $icon)) {
      throw "Launcher icon is missing for ${density}: $icon"
    }
    if ((Get-Item -LiteralPath $icon).Length -lt 100) {
      throw "Launcher icon looks invalid for ${density}: $icon"
    }
  }

  $env:APP_ENVIRONMENT = "production"
  $env:SOCIAL_BACKEND_URL = $ProductionBackendUrl
  $env:BUILD_COMMIT = $head.Substring(0, 12)

  Write-Host "Source provenance verified"
  Write-Host "Branch       : $branch"
  Write-Host "Commit       : $head"
  Write-Host "Version      : $buildName+$buildNumber"
  Write-Host "Backend      : $ProductionBackendUrl"

  Invoke-Checked flutter clean
  Invoke-Checked flutter pub get

  $postPubGetDirty = @(git status --porcelain --untracked-files=all)
  if ($LASTEXITCODE -ne 0) { throw "git status failed after flutter pub get." }
  if ($postPubGetDirty.Count -gt 0) {
    Write-Host ($postPubGetDirty -join [Environment]::NewLine)
    throw "flutter pub get changed the checked-in source/lock state. Commit the dependency result before building production."
  }

  Write-Host "Running release regression guards..."
  Invoke-Checked flutter test test/settings_screen_test.dart test/career_coin_reward_regression_test.dart
  Invoke-Checked pwsh -NoProfile -File (Join-Path $projectRoot "tool\verify_android_release_config.ps1")

  Write-Host "Building production AAB..."
  Invoke-Checked flutter build appbundle --release `
    "--build-name=$buildName" `
    "--build-number=$buildNumber" `
    "--dart-define=APP_ENVIRONMENT=$($env:APP_ENVIRONMENT)" `
    "--dart-define=SOCIAL_BACKEND_URL=$($env:SOCIAL_BACKEND_URL)" `
    "--dart-define=BUILD_COMMIT=$($env:BUILD_COMMIT)"

  $aab = Join-Path $projectRoot "build\app\outputs\bundle\release\app-release.aab"
  if (!(Test-Path -LiteralPath $aab)) {
    throw "Flutter completed but the expected AAB was not created: $aab"
  }

  Invoke-Checked pwsh -NoProfile -File (Join-Path $projectRoot "tool\verify_online_aab.ps1") -Path $aab

  $hash = (Get-FileHash -LiteralPath $aab -Algorithm SHA256).Hash
  $receiptDir = Join-Path $projectRoot "build\release_receipts"
  New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
  $receiptPath = Join-Path $receiptDir "android-$buildNumber.json"
  [ordered]@{
    platform = "android"
    versionName = $buildName
    versionCode = $buildNumber
    gitCommit = $head
    gitCommitShort = $env:BUILD_COMMIT
    branch = $branch
    backend = $ProductionBackendUrl
    aabPath = $aab
    aabSha256 = $hash
    createdAtUtc = [DateTime]::UtcNow.ToString("o")
  } | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8

  Write-Host ""
  Write-Host "=== PRODUCTION AAB READY ==="
  Write-Host "AAB     : $aab"
  Write-Host "SHA-256 : $hash"
  Write-Host "Commit  : $head"
  Write-Host "Version : $buildName+$buildNumber"
  Write-Host "Receipt : $receiptPath"
  Write-Host "Upload ONLY this AAB to Google Play."
}
finally {
  Pop-Location
}
