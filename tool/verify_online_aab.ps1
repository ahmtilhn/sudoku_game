param(
  [Parameter(Mandatory=$true)]
  [string]$Path,
  [string]$ExpectedSha256
)

$ErrorActionPreference = "Stop"
if (!(Test-Path -LiteralPath $Path)) {
  throw "AAB not found: $Path"
}

$item = Get-Item -LiteralPath $Path
$hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
Write-Host "Path: $($item.FullName)"
Write-Host "Size: $($item.Length)"
Write-Host "SHA-256: $hash"
keytool -printcert -jarfile $item.FullName | Select-String -Pattern "SHA1:|SHA256:" | ForEach-Object { $_.Line.Trim() }
Select-String -Path pubspec.yaml -Pattern "^version:"

if ($ExpectedSha256 -and $hash -ne $ExpectedSha256) {
  throw "AAB SHA-256 mismatch."
}
