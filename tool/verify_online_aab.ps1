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

$scanRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sudoku-aab-scan-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scanRoot | Out-Null
Expand-Archive -LiteralPath $Path -DestinationPath $scanRoot -Force

$scanTargets = @()
$candidateRoots = @(
  (Join-Path $scanRoot "base\assets"),
  (Join-Path $scanRoot "base\lib"),
  (Join-Path $scanRoot "base\res"),
  (Join-Path $scanRoot "base\resources.pb")
)
foreach ($candidate in $candidateRoots) {
  if (Test-Path -LiteralPath $candidate) {
    $item = Get-Item -LiteralPath $candidate
    if ($item.PSIsContainer) {
      $scanTargets += Get-ChildItem -LiteralPath $candidate -Recurse -File
    } else {
      $scanTargets += $item
    }
  }
}

function Assert-ArtifactDoesNotContain {
  param([string]$Label, [string]$Pattern)
  $matches = $scanTargets | Select-String -Pattern $Pattern -SimpleMatch -List
  if ($matches) {
    $paths = ($matches | ForEach-Object { $_.Path.Replace($scanRoot, "<aab>") }) -join ", "
    throw "Release AAB contains blocked ${Label}: $paths"
  }
}

Assert-ArtifactDoesNotContain "staging backend URL" "sudoku-duel-social-staging"
Assert-ArtifactDoesNotContain "localhost HTTP endpoint" "http://localhost"
Assert-ArtifactDoesNotContain "localhost HTTPS endpoint" "https://localhost"
Assert-ArtifactDoesNotContain "localhost WebSocket endpoint" "ws://localhost"
Assert-ArtifactDoesNotContain "localhost secure WebSocket endpoint" "wss://localhost"
Assert-ArtifactDoesNotContain "local IPv4 HTTP endpoint" "http://127.0.0.1"
Assert-ArtifactDoesNotContain "local IPv4 HTTPS endpoint" "https://127.0.0.1"
Assert-ArtifactDoesNotContain "local IPv4 WebSocket endpoint" "ws://127.0.0.1"
Assert-ArtifactDoesNotContain "local IPv4 secure WebSocket endpoint" "wss://127.0.0.1"
Assert-ArtifactDoesNotContain "Google test AdMob publisher ID" "ca-app-pub-3940256099942544"
Assert-ArtifactDoesNotContain "Meta client token placeholder" "REPLACE_WITH_META_CLIENT_TOKEN"
Assert-ArtifactDoesNotContain "Meta app ID placeholder" "fb000000000000000"
Assert-ArtifactDoesNotContain "debug unlimited coins flag" "DEBUG_UNLIMITED_COINS=true"

if ($ExpectedSha256 -and $hash -ne $ExpectedSha256) {
  throw "AAB SHA-256 mismatch."
}
