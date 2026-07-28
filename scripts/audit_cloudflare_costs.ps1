param(
  [string]$WorkerDir = "backend/social_worker",
  [string]$Config = "wrangler.staging.toml",
  [string]$Database = "",
  [int]$CleanupLimit = 500
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$workerPath = Resolve-Path (Join-Path $root $WorkerDir)
$configPath = Join-Path $workerPath $Config
if (-not (Test-Path $configPath)) {
  $configPath = Join-Path $workerPath "wrangler.example.toml"
}

$wrangler = Join-Path $workerPath "node_modules/.bin/wrangler.cmd"
if (-not (Test-Path $wrangler)) {
  $wrangler = "wrangler"
}

if ([string]::IsNullOrWhiteSpace($Database)) {
  $configText = Get-Content $configPath -Raw
  $match = [regex]::Match($configText, 'database_name\s*=\s*"([^"]+)"')
  if (-not $match.Success) {
    throw "database_name not found in $configPath"
  }
  $Database = $match.Groups[1].Value
}

function Invoke-D1Sql {
  param([string]$Sql)
  & $wrangler d1 execute $Database --local --config $configPath --command $Sql
}

Write-Output "Cloudflare cost audit"
Write-Output "WorkerDir: $workerPath"
Write-Output "Config: $configPath"
Write-Output "Database: $Database"
Write-Output ""

Write-Output "===== D1 schema/index list ====="
Invoke-D1Sql "SELECT type, name, tbl_name FROM sqlite_master WHERE type IN ('table','index') ORDER BY type, tbl_name, name;"

Write-Output "===== EXPLAIN QUERY PLAN checks ====="
$queries = @(
  "EXPLAIN QUERY PLAN SELECT id FROM players WHERE firebase_uid = 'uid' LIMIT 1;",
  "EXPLAIN QUERY PLAN SELECT id FROM players WHERE username_normalized LIKE 'abc%' ORDER BY rating DESC LIMIT 20;",
  "EXPLAIN QUERY PLAN SELECT room_id FROM matches WHERE (player_a_id = 'p1' OR player_b_id = 'p1') AND status IN ('waiting','countdown','active','paused') ORDER BY created_at DESC LIMIT 1;",
  "EXPLAIN QUERY PLAN SELECT player_id, rating FROM ranked_queue WHERE difficulty = 'easy' AND player_id != 'p1' AND room_id IS NULL ORDER BY rating, joined_at LIMIT 1;",
  "EXPLAIN QUERY PLAN SELECT id FROM challenges WHERE status IN ('declined','expired','cancelled','completed') AND updated_at < '2026-01-01T00:00:00.000Z' LIMIT $CleanupLimit;",
  "EXPLAIN QUERY PLAN SELECT id FROM rematch_invitations WHERE status IN ('accepted','declined','expired','cancelled','insufficient_coins') AND updated_at < '2026-01-01T00:00:00.000Z' LIMIT $CleanupLimit;",
  "EXPLAIN QUERY PLAN SELECT id FROM device_tokens WHERE enabled = 0 AND updated_at < '2026-01-01T00:00:00.000Z' LIMIT $CleanupLimit;",
  "EXPLAIN QUERY PLAN SELECT key FROM request_limits WHERE window_started_at < 1 LIMIT $CleanupLimit;"
)
foreach ($query in $queries) {
  Write-Output ""
  Write-Output $query
  Invoke-D1Sql $query
}

Write-Output ""
Write-Output "===== stale row counts ====="
Invoke-D1Sql @"
SELECT 'request_limits_older_48h' AS metric, COUNT(*) AS count
FROM request_limits
WHERE window_started_at < strftime('%s','now','-48 hours')
UNION ALL
SELECT 'disabled_tokens_older_7d', COUNT(*)
FROM device_tokens
WHERE enabled = 0 AND updated_at < datetime('now','-7 days')
UNION ALL
SELECT 'terminal_challenges_older_30d', COUNT(*)
FROM challenges
WHERE status IN ('declined','expired','cancelled','completed')
  AND updated_at < datetime('now','-30 days')
UNION ALL
SELECT 'terminal_rematches_older_30d', COUNT(*)
FROM rematch_invitations
WHERE status IN ('accepted','declined','expired','cancelled','insufficient_coins')
  AND updated_at < datetime('now','-30 days')
UNION ALL
SELECT 'expired_reward_claims_older_7d', COUNT(*)
FROM reward_claims
WHERE status IN ('prepared','expired')
  AND expires_at IS NOT NULL
  AND expires_at < datetime('now','-7 days')
UNION ALL
SELECT 'transient_audit_older_30d', COUNT(*)
FROM match_audit
WHERE event_timestamp < datetime('now','-30 days');
"@

Write-Output ""
Write-Output "===== local database size ====="
$stateDir = Join-Path $workerPath ".wrangler/state/v3/d1"
if (Test-Path $stateDir) {
  Get-ChildItem $stateDir -Recurse -File |
    Sort-Object Length -Descending |
    Select-Object -First 20 FullName, Length
} else {
  Write-Output "No local D1 state directory found."
}

Write-Output ""
Write-Output "===== known full-scan query grep ====="
rg -n "SELECT \*|LIKE \?|\bOFFSET\b|DELETE FROM .*WHERE" "$workerPath/src" "$workerPath/migrations" |
  Select-Object -First 200

Write-Output ""
Write-Output "Audit complete. Review EXPLAIN output manually; do not claim percent savings without rows_read/rows_written measurements."
