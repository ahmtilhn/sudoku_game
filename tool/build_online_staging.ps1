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
if ($BackendUrl -match "REPLACE_WITH|localhost|127\.0\.0\.1|gercek-production-worker-adresi|example") {
  throw "BackendUrl must be a real non-placeholder HTTPS staging URL."
}
if ($uri.Host -notmatch "staging") {
  throw "Internal testing builds must use a staging backend host."
}

$commit = (git rev-parse HEAD).Trim()
if ($commit -notmatch "^[0-9a-fA-F]{7,40}$") {
  throw "Unable to resolve the current Git commit SHA."
}

$normalized = $uri.GetLeftPart([System.UriPartial]::Authority)
Write-Host "Building Play internal-testing AAB"
Write-Host "Backend: $normalized"
Write-Host "Commit: $commit"

flutter build appbundle --release `
  --dart-define="APP_ENVIRONMENT=staging" `
  --dart-define="INTERNAL_TESTING=true" `
  --dart-define="SOCIAL_BACKEND_URL=$normalized" `
  --dart-define="BUILD_COMMIT=$commit"
