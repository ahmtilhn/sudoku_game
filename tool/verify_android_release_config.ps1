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
$expectedPlaySigningSha1 = "53:B0:F0:FF:89:6C:50:AE:B0:86:F2:04:A2:2E:ED:E2:9F:1B:F3:0B"

$googleServicesPath = Join-Path $ProjectRoot "android\app\google-services.json"
$servicesXmlPath = Join-Path $ProjectRoot "android\app\src\main\res\values\services.xml"
$buildGradlePath = Join-Path $ProjectRoot "android\app\build.gradle.kts"

foreach ($path in @($googleServicesPath, $servicesXmlPath, $buildGradlePath)) {
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
$backendMatch = [regex]::Match(
  $buildGradleText,
  '(?s)val\s+defaultSocialBackendUrl\s*=\s*"([^"]+)"'
)
if (!$backendMatch.Success) {
  throw "build.gradle.kts does not define the default Android social backend."
}
if ($buildGradleText -notmatch 'tasks\.withType<FlutterTask>\(\)' -or
    $buildGradleText -notmatch 'withDefaultSocialBackend\(dartDefines\)') {
  throw "The release Flutter task does not merge the default SOCIAL_BACKEND_URL."
}
if ($buildGradleText -notmatch [regex]::Escape($expectedPlayGamesServerClientId)) {
  throw "build.gradle.kts does not pin the expected Play Games game-server OAuth client."
}

$backendUrl = $backendMatch.Groups[1].Value
$backendUri = $null
if (![Uri]::TryCreate($backendUrl, [UriKind]::Absolute, [ref]$backendUri) -or
    $backendUri.Scheme -ne "https" -or
    [string]::IsNullOrWhiteSpace($backendUri.Host) -or
    $backendUri.UserInfo -or
    $backendUri.Query -or
    $backendUri.Fragment -or
    $backendUrl -match "localhost|127\.0\.0\.1|replace_with|example") {
  throw "The default SOCIAL_BACKEND_URL must be a real HTTPS endpoint without credentials or query data."
}

Write-Host "Android release configuration verified."
Write-Host "Firebase project : $expectedFirebaseProjectId ($expectedFirebaseProjectNumber)"
Write-Host "Firebase app     : $expectedFirebaseAppId"
Write-Host "Package          : $expectedPackage"
Write-Host "Play Games ID    : $playGamesProjectId"
Write-Host "Server OAuth     : $playGamesServerClientId"
Write-Host "Social backend   : $($backendUri.GetLeftPart([UriPartial]::Authority))"
Write-Host "Play signing SHA1: $expectedPlaySigningSha1"
Write-Host "Console-only checks still required: Firebase Auth Play Games provider uses this client and current secret; Play Games Android credential/test access; Firebase App Check SHA-256."
