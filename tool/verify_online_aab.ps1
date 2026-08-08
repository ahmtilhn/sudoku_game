param(
  [Parameter(Mandatory=$true)]
  [string]$Path,
  [string]$ExpectedSha256
)

$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "verify_android_release_config.ps1")

if (!(Test-Path -LiteralPath $Path)) {
  throw "AAB not found: $Path"
}

$item = Get-Item -LiteralPath $Path
$hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Write-Host ""
Write-Host "AAB artifact"
Write-Host "Path: $($item.FullName)"
Write-Host "Size: $($item.Length)"
Write-Host "SHA-256: $hash"
Write-Host "Version:"
Select-String -Path (Join-Path $projectRoot "pubspec.yaml") -Pattern "^version:"

Write-Host ""
Write-Host "Local AAB signature (UPLOAD KEY, not the Play-delivered app certificate):"
$keytoolOutput = keytool -printcert -jarfile $item.FullName 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "keytool could not inspect the AAB signature: $keytoolOutput"
}
$keytoolOutput | Select-String -Pattern "SHA1:|SHA256:" | ForEach-Object {
  Write-Host $_.Line.Trim()
}

Write-Host ""
Write-Host "Google Play re-signs delivered APKs with the Play app-signing key."
Write-Host "Expected classic Play app-signing SHA-1:"
Write-Host "C0:4C:3A:AB:7D:76:6C:2E:87:C9:53:98:EB:4B:59:97:52:CD:25:A1"

if ($ExpectedSha256 -and $hash -ne $ExpectedSha256) {
  throw "AAB SHA-256 mismatch."
}
