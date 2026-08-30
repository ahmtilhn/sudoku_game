import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = fileURLToPath(new URL('.', import.meta.url));
const workerRoot = resolve(testDir, '..');
const repoRoot = resolve(workerRoot, '../..');

function workerFile(path: string): string {
  return readFileSync(resolve(workerRoot, path), 'utf8');
}

function repoFile(path: string): string {
  return readFileSync(resolve(repoRoot, path), 'utf8');
}

describe('achievement integrity', () => {
  it('replaces the classic9-only reward trigger with variant aggregate progress', () => {
    const migration = workerFile('migrations/0028_achievement_integrity.sql');

    expect(migration).toContain('DROP TRIGGER IF EXISTS auto_grant_coin_achievement_rewards');
    expect(migration).toContain('AFTER UPDATE OF rating, games_played, wins ON player_variant_ratings');
    expect(migration).toContain("v.scope = 'global'");
    expect(migration).toContain('COALESCE(SUM(v.wins), 0)');
    expect(migration).toContain('COALESCE(SUM(v.games_played), 0)');
    expect(migration).toContain('COALESCE(MAX(v.rating), 0)');
    expect(migration).toContain("'first_win', 'wins_10', 'games_25', 'wins_50'");
    expect(migration).toContain("'rating_1200', 'rating_1500', 'wins_250'");
  });

  it('unlocks and pays automatic achievements exactly once in one database transaction', () => {
    const migration = workerFile('migrations/0028_achievement_integrity.sql');

    expect(migration).toContain("NEW.source = 'automatic'");
    expect(migration).toContain("'achievement:' || NEW.player_id || ':' || NEW.achievement_id");
    expect(migration).toContain("'achievement_reward'");
    expect(migration).toContain('INSERT OR IGNORE INTO coin_ledger');
    expect(migration).toContain('INSERT OR IGNORE INTO reward_claims');
    expect(migration).toContain('CREATE TRIGGER achievement_count_after_unlock');
  });

  it('earns Friendly Rival for both players and removes inactive future achievements', () => {
    const migration = workerFile('migrations/0028_achievement_integrity.sql');

    expect(migration).toContain('CREATE TRIGGER friend_link_after_accept');
    expect(migration).toContain("SELECT NEW.player_low_id, 'friend_link'");
    expect(migration).toContain("SELECT NEW.player_high_id, 'friend_link'");
    expect(migration).toContain("id IN ('country_contributor', 'tournament_podium')");
  });

  it('keeps the runtime safety net aligned with the canonical migration', () => {
    const runtime = workerFile('src/achievement_integrity.ts');
    const entry = workerFile('src/entry_v2.ts');

    expect(runtime).toContain("const SCHEMA_KEY = 'achievement_integrity'");
    expect(runtime).toContain('achievement_unlock_from_variant_progress');
    expect(runtime).toContain('achievement_reward_after_automatic_unlock');
    expect(runtime).toContain('friend_link_after_accept');
    expect(entry).toContain("import { ensureAchievementIntegrity } from './achievement_integrity'");
    expect(entry.match(/await ensureAchievementIntegrity\(env\);/g)?.length).toBe(2);
  });

  it('maps only the real exported Google Play achievement and blocks implicit local unlocks', () => {
    const gamesIds = repoFile('android/app/src/main/res/values/games-ids.xml');
    const services = repoFile('android/app/src/main/res/values/services.xml');
    const sync = repoFile('lib/services/achievement_sync_service.dart');
    const bridge = repoFile('lib/services/platform_game_services.dart');
    const leaderboard = repoFile('lib/services/platform_leaderboard_service.dart');

    const exportedId = 'CgkIzMyzm9saEAIQSg';
    expect(gamesIds).toContain(`<string name="achievement_first_victory" translatable="false">${exportedId}</string>`);
    expect(services).toContain(`<string name="achievement_first_win" translatable="false">${exportedId}</string>`);
    expect(sync).toContain(`'${exportedId}'`);
    expect(sync).toContain("item['id']?.toString() == 'first_win'");
    expect(bridge).toContain('if (normalized == null || normalized.isEmpty)');
    expect(bridge).toContain('return Future<bool>.value(false);');
    expect(leaderboard).toContain('syncNow(retryForSettlement: true)');
  });

  it('disables the unfinished backend mirror queue instead of claiming unsupported Play mappings', () => {
    const migration = workerFile('migrations/0028_achievement_integrity.sql');
    const runtime = workerFile('src/achievement_integrity.ts');

    expect(migration).toContain('platform_mirror_enabled = 0');
    expect(migration).toContain('DELETE FROM platform_achievement_mirror_queue');
    expect(runtime).toContain('platform_mirror_enabled = 0');
    expect(runtime).toContain('DELETE FROM platform_achievement_mirror_queue');
  });
});
