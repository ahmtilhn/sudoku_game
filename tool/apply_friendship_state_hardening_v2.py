from __future__ import annotations

from pathlib import Path
import runpy


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one replacement target, found {count}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Apply the full v1 patch first.
runpy.run_path("tool/apply_friendship_state_hardening.py", run_name="__main__")

friend_path = Path("backend/social_worker/src/friend_notifications.ts")
friend_text = friend_path.read_text(encoding="utf-8")

# Preserve the legacy 20/hour contract while returning a proper 429 response
# instead of allowing a generic exception to become a 500.
old_rate_call = """  await enforceRateLimit(env, `friend:${actor.id}`, 20, 3600);\n\n  const targetPublicId = requiredPublicId(body.targetPublicId);\n"""
new_rate_call = """  const rateLimitAllowed = await consumeRateLimit(\n    env,\n    `friend:${actor.id}`,\n    20,\n    3600,\n  );\n  if (!rateLimitAllowed) {\n    return jsonLike(authResponse, 429, {\n      error: 'Too many requests. Try again later.',\n      code: 'friend_request_rate_limited',\n    });\n  }\n\n  const targetPublicId = requiredPublicId(body.targetPublicId);\n"""
if friend_text.count(old_rate_call) != 1:
    raise RuntimeError("friend_notifications.ts: rate-limit call target mismatch")
friend_text = friend_text.replace(old_rate_call, new_rate_call, 1)

old_rate_function = """async function enforceRateLimit(\n  env: FriendNotificationEnv,\n  key: string,\n  limit: number,\n  windowSeconds: number,\n): Promise<void> {\n  const now = Math.floor(Date.now() / 1000);\n  const current = await env.DB.prepare(\n    'SELECT window_started_at, count FROM request_limits WHERE key = ?',\n  )\n    .bind(key)\n    .first<{ window_started_at: number; count: number }>();\n\n  if (!current || now - current.window_started_at >= windowSeconds) {\n    await env.DB.prepare(\n      `INSERT INTO request_limits (key, window_started_at, count)\n       VALUES (?, ?, 1)\n       ON CONFLICT(key) DO UPDATE SET\n         window_started_at = excluded.window_started_at,\n         count = 1`,\n    )\n      .bind(key, now)\n      .run();\n    return;\n  }\n\n  if (current.count >= limit) {\n    throw new Error('friend_request_rate_limited');\n  }\n  await env.DB.prepare(\n    'UPDATE request_limits SET count = count + 1 WHERE key = ?',\n  )\n    .bind(key)\n    .run();\n}\n"""
new_rate_function = """async function consumeRateLimit(\n  env: FriendNotificationEnv,\n  key: string,\n  limit: number,\n  windowSeconds: number,\n): Promise<boolean> {\n  const now = Math.floor(Date.now() / 1000);\n  const current = await env.DB.prepare(\n    'SELECT window_started_at, count FROM request_limits WHERE key = ?',\n  )\n    .bind(key)\n    .first<{ window_started_at: number; count: number }>();\n\n  if (!current || now - current.window_started_at >= windowSeconds) {\n    await env.DB.prepare(\n      `INSERT INTO request_limits (key, window_started_at, count)\n       VALUES (?, ?, 1)\n       ON CONFLICT(key) DO UPDATE SET\n         window_started_at = excluded.window_started_at,\n         count = 1`,\n    )\n      .bind(key, now)\n      .run();\n    return true;\n  }\n\n  if (current.count >= limit) return false;\n  await env.DB.prepare(\n    'UPDATE request_limits SET count = count + 1 WHERE key = ?',\n  )\n    .bind(key)\n    .run();\n  return true;\n}\n"""
if friend_text.count(old_rate_function) != 1:
    raise RuntimeError("friend_notifications.ts: rate-limit function target mismatch")
friend_text = friend_text.replace(old_rate_function, new_rate_function, 1)

# The recent-opponent query has exactly 12 placeholders. Ensure the generated
# bind list has exactly 12 actor ids as well.
recent_start = friend_text.index("async function handleRecentOpponents")
recent_end = friend_text.index("function playerJson", recent_start)
recent = friend_text[recent_start:recent_end]
old_bind = "    .bind(\n" + ("      actor.id,\n" * 13) + "    )"
new_bind = "    .bind(\n" + ("      actor.id,\n" * 12) + "    )"
if recent.count(old_bind) != 1:
    raise RuntimeError("friend_notifications.ts: recent opponent bind list mismatch")
recent = recent.replace(old_bind, new_bind, 1)
friend_text = friend_text[:recent_start] + recent + friend_text[recent_end:]
friend_path.write_text(friend_text, encoding="utf-8")

# v1 intentionally used raw triple-quoted strings; remove the accidental first
# backslash that was emitted by that construction.
for test_path in (
    "backend/social_worker/test/friendship_hardening.test.ts",
    "test/friendship_state_hardening_test.dart",
):
    path = Path(test_path)
    text = path.read_text(encoding="utf-8")
    if text.startswith("\\\n"):
        text = text[2:]
    path.write_text(text.lstrip("\n"), encoding="utf-8")

# Make the source-contract assertions resilient to dart format line wrapping.
dart_test = Path("test/friendship_state_hardening_test.dart")
dart_text = dart_test.read_text(encoding="utf-8")
dart_text = dart_text.replace(
    "expect(source, contains(\"? () => _respondRequest(p, true)\"));",
    "expect(source, contains('_respondRequest(p, true)'));",
)
dart_text = dart_text.replace(
    "expect(source, contains(\"? () => _respondRequest(p, false)\"));",
    "expect(source, contains('_respondRequest(p, false)'));",
)
dart_test.write_text(dart_text, encoding="utf-8")

print("Friendship state hardening v2 patch applied successfully.")
