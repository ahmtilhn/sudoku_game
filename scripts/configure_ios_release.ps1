[CmdletBinding()]
param(
    [string]$LeaderboardId = $env:IOS_GAME_CENTER_LEADERBOARD_ID,
    [string]$AchievementFirstWinId = $env:IOS_GAME_CENTER_ACHIEVEMENT_FIRST_WIN_ID,
    [string]$ConfigPath = 'ios/Flutter/Release.xcconfig'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ([string]::IsNullOrWhiteSpace($LeaderboardId) -or $LeaderboardId -match 'REPLACE_') {
    throw 'IOS_GAME_CENTER_LEADERBOARD_ID is required.'
}
if ([string]::IsNullOrWhiteSpace($AchievementFirstWinId) -or $AchievementFirstWinId -match 'REPLACE_') {
    throw 'IOS_GAME_CENTER_ACHIEVEMENT_FIRST_WIN_ID is required.'
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Missing iOS release config: $ConfigPath"
}

$content = Get-Content -LiteralPath $ConfigPath -Raw
$content = [regex]::Replace(
    $content,
    '(?m)^INFOPLIST_KEY_SudokuLeaderboardGlobalRating\s*=.*$',
    "INFOPLIST_KEY_SudokuLeaderboardGlobalRating = $LeaderboardId"
)
$content = [regex]::Replace(
    $content,
    '(?m)^INFOPLIST_KEY_SudokuAchievementFirstWin\s*=.*$',
    "INFOPLIST_KEY_SudokuAchievementFirstWin = $AchievementFirstWinId"
)
Set-Content -LiteralPath $ConfigPath -Value $content -NoNewline

Write-Host 'Configured iOS Game Center release identifiers.' -ForegroundColor Green
