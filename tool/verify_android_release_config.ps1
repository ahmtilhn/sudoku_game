param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"

$expectedPackage = "com.devoviastudio.sudoku"
$expectedFirebaseProjectId = "focus-sweep-503417-d7"
$expectedFirebaseProjectNumber = "31445697560"
$expectedFirebaseAppId = "1:31445697560:android:ed951eabf51d75800b2f6d"
$expectedPlayGamesProjectId = "917838292556"
$expectedPlayGamesServerClientId = "917838292556-bbq7a36t2kulodpqfd9p3aqkkcs58jhj.apps.googleusercontent.com"
$expectedPlaySigningSha1 = "C0:4C:3A:AB:7D:76:6C:2E:87:C9:53:98:EB:4B:59:97:52:CD:25:A1"
$expectedAndroidAdMobAppId = "ca-app-pub-8422988604275177~6950938184"
$expectedIosAdMobAppId = "ca-app-pub-8422988604275177~3293784266"
$expectedIosRewardedId = "ca-app-pub-8422988604275177/3366916396"
$expectedIosRewardedInterstitialId = "ca-app-pub-8422988604275177/4982984468"

$googleServicesPath = Join-Path $ProjectRoot "android\app\google-services.json"
$servicesXmlPath = Join-Path $ProjectRoot "android\app\src\main\res\values\services.xml"
$buildGradlePath = Join-Path $ProjectRoot "android\app\build.gradle.kts"
$iosInfoPlistPath = Join-Path $ProjectRoot "ios\Runner\Info.plist"
$adsServicePath = Join-Path $ProjectRoot "lib\services\ads_service.dart"

foreach ($path in @($googleServicesPath, $servicesXmlPath, $buildGradlePath, $iosInfoPlistPath, $adsServicePath)) {
  if (!(Test-Path -LiteralPath $path)) {
    throw "Required release configuration file is missing: $path"
  }
}

$googleServices = Get-Content -LiteralPath $googleServicesPath -Raw | ConvertFrom-Json
if ($googleServices.project_info.project_id -ne $expectedFirebaseProjectId -or
    [string]$googleServices.project_info.project_number -ne $expectedFirebaseProjectNumber) {
  throw "google-services.json belongs to the wrong Firebase project."
}

$androidClient = @($googleServices.client) | Where-Object {
  $_.client_info.android_client_info.package_name -eq $expectedPackage
} | Select-Object -First 1
if ($null -eq $androidClient) {
  throw "google-services.json has no Android client for $expectedPackage."
}
if ($androidClient.client_info.mobilesdk_app_id -ne $expectedFirebaseAppId) {
  throw "The Firebase Android App ID is not $expectedFirebaseAppId."
}

$servicesText = Get-Content -LiteralPath $servicesXmlPath -Raw
function Read-XmlString([string]$Name) {
  $pattern = '<string\s+name="' + [regex]::Escape($Name) + '"[^>]*>([^<]+)</string>'
  $match = [regex]::Match($servicesText, $pattern)
  if (!$match.Success) {
    throw "Missing Android string resource: $Name"
  }
  return $match.Groups[1].Value.Trim()
}

$playGamesProjectId = Read-XmlString "game_services_project_id"
$playGamesServerClientId = Read-XmlString "game_services_web_client_id"
if ($playGamesProjectId -ne $expectedPlayGamesProjectId) {
  throw "The Play Games project ID must be $expectedPlayGamesProjectId."
}
if ($playGamesServerClientId -ne $expectedPlayGamesServerClientId) {
  throw "The Play Games game-server OAuth client must be $expectedPlayGamesServerClientId."
}

# The Firebase Android application and Play Games project deliberately live in
# separate Google Cloud projects. google-services.json remains the Firebase
# runtime configuration and therefore does not need to contain the Play Games
# game-server OAuth client. That client is configured manually in Play Console
# and in Firebase Authentication's Play Games provider. Its secret must never be
# stored in this repository.

$buildGradleText = Get-Content -LiteralPath $buildGradlePath -Raw
if ($buildGradleText -match 'defaultSocialBackendUrl' -or
    $buildGradleText -match 'withDefaultSocialBackend' -or
    $buildGradleText -match 'sudoku-duel-social-staging') {
  throw "Release build.gradle.kts must not define or inject a staging social backend fallback."
}
if ($buildGradleText -notmatch 'tasks\.withType<FlutterTask>\(\)' -or
    $buildGradleText -notmatch 'assertProductionReleaseDefines\(effectiveDefines\)') {
  throw "The release Flutter task does not validate explicit production dart-defines."
}
foreach ($requiredDefine in @('APP_ENVIRONMENT=production', 'BUILD_COMMIT', 'SOCIAL_BACKEND_URL')) {
  if ($buildGradleText -notmatch [regex]::Escape($requiredDefine)) {
    throw "build.gradle.kts does not require $requiredDefine for release builds."
  }
}
if ($servicesText -match 'REPLACE_WITH_META_CLIENT_TOKEN|000000000000000|fb000000000000000') {
  throw "Android release services.xml still contains Meta placeholder values."
}
if ($buildGradleText -notmatch [regex]::Escape($expectedPlayGamesServerClientId)) {
  throw "build.gradle.kts does not pin the expected Play Games game-server OAuth client."
}

$androidAdMobAppId = Read-XmlString "admob_app_id"
if ($androidAdMobAppId -ne $expectedAndroidAdMobAppId) {
  throw "Android AdMob App ID must be $expectedAndroidAdMobAppId."
}

$iosInfoPlistText = Get-Content -LiteralPath $iosInfoPlistPath -Raw
if ($iosInfoPlistText -notmatch [regex]::Escape("<key>GADApplicationIdentifier</key>") -or
    $iosInfoPlistText -notmatch [regex]::Escape("<string>$expectedIosAdMobAppId</string>")) {
  throw "iOS Info.plist must contain production GADApplicationIdentifier $expectedIosAdMobAppId."
}
if ($iosInfoPlistText -match "ca-app-pub-3940256099942544") {
  throw "iOS Info.plist still contains a Google test AdMob ID."
}

$adsServiceText = Get-Content -LiteralPath $adsServicePath -Raw
foreach ($expectedAdUnit in @($expectedIosRewardedId, $expectedIosRewardedInterstitialId)) {
  if ($adsServiceText -notmatch [regex]::Escape($expectedAdUnit)) {
    throw "AdsService does not contain expected iOS production AdMob unit $expectedAdUnit."
  }
}

$backendUrl = $env:SOCIAL_BACKEND_URL
if (![string]::IsNullOrWhiteSpace($backendUrl)) {
  $backendUri = $null
  if (![Uri]::TryCreate($backendUrl, [UriKind]::Absolute, [ref]$backendUri) -or
      $backendUri.Scheme -ne "https" -or
      [string]::IsNullOrWhiteSpace($backendUri.Host) -or
      $backendUri.UserInfo -or
      $backendUri.Query -or
      $backendUri.Fragment -or
      $backendUrl -match "localhost|127\.0\.0\.1|replace_with|example|staging|test") {
    throw "SOCIAL_BACKEND_URL must be an explicit production HTTPS endpoint without credentials or query data."
  }
}

Write-Host "Android release configuration verified."
Write-Host "Firebase project : $expectedFirebaseProjectId ($expectedFirebaseProjectNumber)"
Write-Host "Firebase app     : $expectedFirebaseAppId"
Write-Host "Package          : $expectedPackage"
Write-Host "Android AdMob    : $expectedAndroidAdMobAppId"
Write-Host "iOS AdMob        : $expectedIosAdMobAppId"
Write-Host "iOS rewarded     : $expectedIosRewardedId"
Write-Host "iOS rewarded int : $expectedIosRewardedInterstitialId"
Write-Host "Play Games ID    : $playGamesProjectId"
Write-Host "Server OAuth     : $playGamesServerClientId"
if (![string]::IsNullOrWhiteSpace($backendUrl)) {
  Write-Host "Social backend   : $($backendUri.GetLeftPart([UriPartial]::Authority))"
} else {
  Write-Host "Social backend   : explicit production dart-define required at build time"
}
Write-Host "Play signing SHA1: $expectedPlaySigningSha1"
Write-Host "Console-only checks still required: Firebase Auth Play Games provider uses this client and current secret; Play Games Android credential/test access; Firebase App Check SHA-256."
