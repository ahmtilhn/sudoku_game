$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$results = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    $results.Add([pscustomobject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
    })
}

function Test-FileExists {
    param([string]$Name, [string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Add-Check $Name 'PASS' "Present: $Path"
    } else {
        Add-Check $Name 'FAIL' "Missing: $Path"
    }
}

function Test-NoPattern {
    param([string]$Name, [string]$Path, [string]$Pattern, [string]$FailDetail)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Check $Name 'FAIL' "Missing file: $Path"
        return
    }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -match $Pattern) {
        Add-Check $Name 'FAIL' $FailDetail
    } else {
        Add-Check $Name 'PASS' "No blocked placeholder/test value found in $Path"
    }
}

function Test-Contains {
    param([string]$Name, [string]$Path, [string]$Pattern, [string]$MissingDetail)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Check $Name 'FAIL' "Missing file: $Path"
        return
    }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -match $Pattern) {
        Add-Check $Name 'PASS' "Verified in $Path"
    } else {
        Add-Check $Name 'FAIL' $MissingDetail
    }
}

Test-FileExists 'Android release signing config' 'android/key.properties'
Test-NoPattern 'Android AdMob App ID is production' 'android/app/src/main/res/values/services.xml' 'ca-app-pub-3940256099942544~' 'Android services.xml still contains a Google test AdMob App ID.'
Test-NoPattern 'Android Meta App ID is configured or SDK removed' 'android/app/src/main/res/values/services.xml' '000000000000000|REPLACE_WITH_META_CLIENT_TOKEN' 'Android services.xml still contains Meta placeholder values.'
Test-NoPattern 'Play Games project is configured' 'android/app/src/main/res/values/services.xml' '0000000000|REPLACE_WITH_PGS_WEB_CLIENT_ID' 'Play Games project or web client ID is still a placeholder.'
Test-NoPattern 'Play Games leaderboard is configured' 'android/app/src/main/res/values/services.xml' 'REPLACE_WITH_LEADERBOARD_ID' 'Play Games leaderboard ID is still a placeholder.'
Test-NoPattern 'Play Games achievement is configured' 'android/app/src/main/res/values/services.xml' 'REPLACE_WITH_ACHIEVEMENT_ID' 'Play Games achievement ID is still a placeholder.'
Test-NoPattern 'iOS AdMob App ID is production' 'ios/Runner/Info.plist' 'ca-app-pub-3940256099942544~' 'iOS Info.plist still contains a Google test AdMob App ID.'
Test-NoPattern 'iOS Meta App ID is configured or SDK removed' 'ios/Runner/Info.plist' '000000000000000|REPLACE_WITH_META_CLIENT_TOKEN' 'iOS Info.plist still contains Meta placeholder values.'
Test-NoPattern 'iOS Game Center leaderboard is configured' 'ios/Flutter/Release.xcconfig' 'REPLACE_WITH_LEADERBOARD_ID' 'iOS release leaderboard ID is still a placeholder.'
Test-NoPattern 'iOS Game Center achievement is configured' 'ios/Flutter/Release.xcconfig' 'REPLACE_WITH_ACHIEVEMENT_ID' 'iOS release achievement ID is still a placeholder.'
Test-Contains 'Target SDK 36' 'android/app/build.gradle.kts' 'targetSdk = 36' 'Android targetSdk must be 36.'
Test-Contains 'Release build does not use debug signing' 'android/app/build.gradle.kts' 'signingConfigs.getByName\("release"\)' 'Release build must use the private upload signing config.'

Write-Host "`nSudoku Duel release readiness check" -ForegroundColor Cyan
foreach ($result in $results) {
    $color = switch ($result.Status) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        default { 'Red' }
    }
    Write-Host ("[{0}] {1} - {2}" -f $result.Status, $result.Name, $result.Detail) -ForegroundColor $color
}

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
$warnings = @($results | Where-Object { $_.Status -eq 'WARN' })
Write-Host ("`nSummary: {0} PASS, {1} WARN, {2} FAIL" -f ($results.Count - $failed.Count - $warnings.Count), $warnings.Count, $failed.Count)

if ($failed.Count -gt 0) {
    exit 1
}
