#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${CONFIG_PATH:-ios/Flutter/Release.xcconfig}"
LEADERBOARD_ID="${IOS_GAME_CENTER_LEADERBOARD_ID:-}"
ACHIEVEMENT_ID="${IOS_GAME_CENTER_ACHIEVEMENT_FIRST_WIN_ID:-}"

if [[ -z "$LEADERBOARD_ID" || "$LEADERBOARD_ID" == *REPLACE_* ]]; then
  echo "IOS_GAME_CENTER_LEADERBOARD_ID is required." >&2
  exit 1
fi
if [[ -z "$ACHIEVEMENT_ID" || "$ACHIEVEMENT_ID" == *REPLACE_* ]]; then
  echo "IOS_GAME_CENTER_ACHIEVEMENT_FIRST_WIN_ID is required." >&2
  exit 1
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Missing iOS release config: $CONFIG_PATH" >&2
  exit 1
fi

python3 - "$CONFIG_PATH" "$LEADERBOARD_ID" "$ACHIEVEMENT_ID" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
leaderboard = sys.argv[2]
achievement = sys.argv[3]
text = path.read_text(encoding="utf-8")
text = re.sub(
    r"(?m)^INFOPLIST_KEY_SudokuLeaderboardGlobalRating\s*=.*$",
    f"INFOPLIST_KEY_SudokuLeaderboardGlobalRating = {leaderboard}",
    text,
)
text = re.sub(
    r"(?m)^INFOPLIST_KEY_SudokuAchievementFirstWin\s*=.*$",
    f"INFOPLIST_KEY_SudokuAchievementFirstWin = {achievement}",
    text,
)
path.write_text(text, encoding="utf-8")
PY

echo "Configured iOS Game Center release identifiers."
