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

function Test-Contains {
    param([string]$Name, [string]$Path, [string]$Pattern, [string]$MissingDetail)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Check $Name 'FAIL' "Missing file: $Path"
        return
    }
    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -match $Pattern) {
        Add-Check $Name 'PASS' "Documented in $Path"
    } else {
        Add-Check $Name 'FAIL' $MissingDetail
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

Test-FileExists 'Firebase Android config' 'android/app/google-services.json'
Test-FileExists 'Firebase iOS config' 'ios/Runner/GoogleService-Info.plist'
Test-Contains 'Email/Password provider documentation' 'docs/ACCOUNT_PROTECTION_AND_RELEASE_SETUP.md' 'Email/Password provider' 'Email/Password provider setup is not documented.'
Test-Contains 'App Check documentation' 'docs/APP_CHECK_CUSTOM_BACKEND.md' 'ALLOWED_APP_CHECK_APP_IDS' 'App Check backend setup is not documented.'
Test-Contains 'Android AdMob App ID documentation' 'docs/STORE_AND_ADMOB_SETUP_V2.md' 'Android rewarded' 'Android AdMob setup is not documented.'
Test-Contains 'iOS AdMob App ID documentation' 'docs/STORE_AND_ADMOB_SETUP_V2.md' 'iOS rewarded' 'iOS AdMob setup is not documented.'
Test-Contains 'Android rewarded ad unit define' 'docs/STORE_AND_ADMOB_SETUP_V2.md' 'ADMOB_ANDROID_REWARDED_ID' 'Android rewarded ad unit define is not documented.'
Test-Contains 'iOS rewarded ad unit define' 'docs/STORE_AND_ADMOB_SETUP_V2.md' 'ADMOB_IOS_REWARDED_ID' 'iOS rewarded ad unit define is not documented.'
Test-Contains 'Google Play product IDs' 'docs/STORE_AND_ADMOB_SETUP_V2.md' 'coins_100' 'Google Play product IDs are not documented.'
Test-Contains 'Apple product IDs' 'docs/STORE_AND_ADMOB_SETUP_V2.md' 'coins_100' 'Apple product IDs are not documented.'
Test-Contains 'Google service account secret names' 'backend/social_worker/wrangler.example.toml' 'GOOGLE_PLAY_CLIENT_EMAIL' 'Google Play Worker secret names are not listed.'
Test-Contains 'Apple issuer secret name' 'backend/social_worker/wrangler.example.toml' 'APPLE_IAP_ISSUER_ID' 'Apple issuer secret name is not listed.'
Test-Contains 'Apple key ID secret name' 'backend/social_worker/wrangler.example.toml' 'APPLE_IAP_KEY_ID' 'Apple key ID secret name is not listed.'
Test-Contains 'Apple private key secret name' 'backend/social_worker/wrangler.example.toml' 'APPLE_IAP_PRIVATE_KEY' 'Apple private key secret name is not listed.'
Test-Contains 'AdMob SSV configuration' 'docs/STORE_AND_ADMOB_SETUP_V2.md' 'v1/rewards/admob/ssv' 'AdMob SSV callback setup is not documented.'
Test-Contains 'Cloudflare D1 binding' 'backend/social_worker/wrangler.staging.toml' 'binding = "DB"' 'Cloudflare D1 DB binding is missing.'
Test-Contains 'Worker environment config' 'backend/social_worker/wrangler.staging.toml' 'ENVIRONMENT = "staging"' 'Worker staging environment config is missing.'
Test-NoPattern 'Android release AdMob App ID is not Google test ID' 'android/app/src/main/res/values/services.xml' 'ca-app-pub-3940256099942544~' 'Android services.xml still contains a Google test AdMob App ID.'
Test-NoPattern 'iOS release AdMob App ID is not Google test ID' 'ios/Runner/Info.plist' 'ca-app-pub-3940256099942544~' 'iOS Info.plist still contains a Google test AdMob App ID.'
Test-Contains 'Privacy policy/store disclosure documentation' 'docs/PRIVACY_AND_STORE_DISCLOSURES.md' 'Public privacy-policy URL' 'Privacy policy URL verification is not documented.'
Test-Contains 'Account deletion flow documentation' 'docs/PRIVACY_AND_STORE_DISCLOSURES.md' 'Delete player account' 'Account deletion flow is not documented.'
Test-Contains 'Store disclosure documentation' 'docs/PRIVACY_AND_STORE_DISCLOSURES.md' 'Data safety' 'Store disclosure documentation is missing.'

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
