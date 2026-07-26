param(
  [Parameter(Mandatory=$true)]
  [string]$BackendUrl
)

$ErrorActionPreference = "Stop"
$uri = [Uri]$BackendUrl
if ($uri.Scheme -ne "https") {
  throw "BackendUrl must start with https://"
}
if ($uri.Query -or $uri.UserInfo) {
  throw "BackendUrl must not include query strings, usernames, passwords, or tokens."
}
if ($BackendUrl -match "REPLACE_WITH|localhost|127\.0\.0\.1") {
  throw "BackendUrl must be a non-placeholder HTTPS staging URL."
}

$normalized = $uri.GetLeftPart([System.UriPartial]::Authority)
Write-Host "Building online staging AAB for host: $($uri.Host)"
flutter build appbundle --release --dart-define="SOCIAL_BACKEND_URL=$normalized"
