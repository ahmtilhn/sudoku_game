param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"

$expectedPackage = "com.devoviastudio.sudoku"
$expectedProjectId = "focus-sweep-503417-d7"
$expectedProjectNumber = "31445697560"
$expectedAppId = "1:31445697560:android:ed951eabf51d75800b2f6d"
$expectedPlaySigningSha1 = "53:B0:F0:FF:89:6C:50:AE:B0:86:F2:04:A2:2E:ED:E2:9F:1B:F3:0B"

$googleServicesPath = Join-Path $ProjectRoot "android\app\google-services.json"
$servicesXmlPath = Join-Path $ProjectRoot "android\app\src\main\res\values\services.xml"
$gradlePropertiesPath = Join-Path $ProjectRoot "android\gradle.properties"

foreach ($path in @($googleServicesPath, $servicesXmlPath, $gradlePropertiesPath)) {
  if (!(Test-Path -LiteralPath $path)) {
    throw "Required release configuration file is missing: $path"
  }
}

$googleServices = Get-Content -LiteralPath $googleServicesPath -Raw | ConvertFrom-Json
if ($googleServices.project_info.project_id -ne $expectedProjectId -or
    [string]$googleServices.project_info.project_number -ne $expectedProjectNumber) {
  throw "google-services.json belongs to the wrong Firebase project."
}

$androidClient = @($googleServices.client) | Where-Object {
  $_.client_info.android_client_info.package_name -eq $expectedPackage
} | Select-Object -First 1
if ($null -eq $androidClient) {
  throw "google-services.json has no Android client for $expectedPackage."
}
if ($androidClient.client_info.mobilesdk_app_id -ne $expectedAppId) {
  throw "The Firebase Android App ID is not $expectedAppId."
}

$servicesText = Get-Content -LiteralPath $servicesXmlPath -Raw
function Read-XmlString([string]$Name) {
  $match = [regex]::Match(
    $servicesText,
    "<string\s+name=[`\"']$([regex]::Escape($Name))[`\"'][^>]*>([^<]+)</string>"
  )
  if (!$match.Success) {
    throw "Missing Android string resource: $Name"
  }
  return $match.Groups[1].Value.Trim()
}

$playGamesProjectId = Read-XmlString "game_services_project_id"
$playGamesWebClientId = Read-XmlString "game_services_web_client_id"
if ($playGamesProjectId -notmatch "^[0-9]{10,20}$") {
  throw "game_services_project_id must contain only 10-20 digits."
}
if ($playGamesWebClientId -notmatch "^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$") {
  throw "game_services_web_client_id is malformed."
}

$webClientIds = @($androidClient.oauth_client) | Where-Object {
  [int]$_.client_type -eq 3
} | ForEach-Object { [string]$_.client_id }
if ($playGamesWebClientId -notin $webClientIds) {
  throw "The Play Games server OAuth client is not present as a web client in google-services.json."
}

$gradleText = Get-Content -LiteralPath $gradlePropertiesPath -Raw
$dartDefinesMatch = [regex]::Match($gradleText, "(?m)^dart-defines=(.+)$")
if (!$dartDefinesMatch.Success) {
  throw "android/gradle.properties does not embed the release dart-defines."
}

$defines = @{}
foreach ($encoded in $dartDefinesMatch.Groups[1].Value.Trim().Split(',')) {
  try {
    $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded.Trim()))
  } catch {
    throw "A dart-define entry is not valid Base64."
  }
  $separator = $decoded.IndexOf('=')
  if ($separator -le 0) {
    throw "Invalid decoded dart-define: $decoded"
  }
  $defines[$decoded.Substring(0, $separator)] = $decoded.Substring($separator + 1)
}

$backendUrl = [string]$defines["SOCIAL_BACKEND_URL"]
if ([string]::IsNullOrWhiteSpace($backendUrl)) {
  throw "SOCIAL_BACKEND_URL is not embedded in the normal Android release build."
}
$backendUri = $null
if (![Uri]::TryCreate($backendUrl, [UriKind]::Absolute, [ref]$backendUri) -or
    $backendUri.Scheme -ne "https" -or
    [string]::IsNullOrWhiteSpace($backendUri.Host) -or
    $backendUri.UserInfo -or
    $backendUri.Query -or
    $backendUri.Fragment -or
    $backendUrl -match "localhost|127\.0\.0\.1|replace_with|example") {
  throw "SOCIAL_BACKEND_URL must be a real HTTPS endpoint without credentials or query data."
}

$androidOauthClients = @($androidClient.oauth_client) | Where-Object {
  [int]$_.client_type -eq 1
}
if ($androidOauthClients.Count -eq 0) {
  Write-Host "Info: google-services.json has no client_type=1 entry. This is allowed."
  Write-Host "      The Play Games Android OAuth credential must be linked in Play Console."
}

Write-Host "Android release configuration verified."
Write-Host "Firebase project : $expectedProjectId ($expectedProjectNumber)"
Write-Host "Firebase app     : $expectedAppId"
Write-Host "Package          : $expectedPackage"
Write-Host "Play Games ID    : $playGamesProjectId"
Write-Host "Server OAuth     : $playGamesWebClientId"
Write-Host "Social backend   : $($backendUri.GetLeftPart([UriPartial]::Authority))"
Write-Host "Play signing SHA1: $expectedPlaySigningSha1"
Write-Host "Console-only checks still required: Play Games Android credential/test access and Firebase App Check SHA-256."
