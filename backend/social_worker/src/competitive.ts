export type CompetitiveEnv = {
  DB: D1Database;
};

export type CompetitivePlayer = {
  id: string;
  public_id: string;
  username: string;
  display_name: string;
  avatar_key: string;
  country_code?: string | null;
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  achievement_count: number;
  discoverable?: number | null;
  season_peak_rating?: number | null;
  tournament_entries?: number | null;
  tournament_podiums?: number | null;
  country_contributions?: number | null;
};

export type LeaderboardRow = {
  playerId: string;
  rating: number;
  gamesPlayed: number;
  wins: number;
  draws: number;
  updatedAt: string;
};

export type LeaderboardCursor = {
  rating: number;
  gamesPlayed: number;
  wins: number;
  draws: number;
  updatedAt: string;
  playerId: string;
};

export const ACHIEVEMENT_CATEGORIES = [
  'ranked',
  'tournament',
  'country',
  'sudoku',
  'social',
  'season',
] as const;

const PLATFORM_MIRROR_PLATFORMS = ['google_play_games', 'game_center'] as const;

export class CompetitiveError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
  ) {
    super(message);
  }
}

export function rankName(rating: number): string {
  if (rating >= 1800) return 'Master';
  if (rating >= 1500) return 'Platinum';
  if (rating >= 1300) return 'Gold';
  if (rating >= 1100) return 'Silver';
  return 'Bronze';
}

export function winRate(wins: number, losses: number, draws: number): number {
  const games = wins + losses + draws;
  return games <= 0 ? 0 : wins / games;
}

export function compareLeaderboardRows(
  a: LeaderboardRow,
  b: LeaderboardRow,
): number {
  return (
    b.rating - a.rating ||
    b.gamesPlayed - a.gamesPlayed ||
    b.wins - a.wins ||
    b.draws - a.draws ||
    a.updatedAt.localeCompare(b.updatedAt) ||
    a.playerId.localeCompare(b.playerId)
  );
}

export function encodeLeaderboardCursor(row: LeaderboardCursor): string {
  return btoa(JSON.stringify(row));
}

export function decodeLeaderboardCursor(value: string | null): LeaderboardCursor | null {
  if (!value) return null;
  try {
    const decoded = JSON.parse(atob(value)) as Record<string, unknown>;
    const cursor = {
      rating: Number(decoded.rating),
      gamesPlayed: Number(decoded.gamesPlayed),
      wins: Number(decoded.wins),
      draws: Number(decoded.draws),
      updatedAt: String(decoded.updatedAt ?? ''),
      playerId: String(decoded.playerId ?? ''),
    };
    if (
      !Number.isFinite(cursor.rating) ||
      !Number.isFinite(cursor.gamesPlayed) ||
      !Number.isFinite(cursor.wins) ||
      !Number.isFinite(cursor.draws) ||
      cursor.updatedAt.length === 0 ||
      cursor.playerId.length === 0
    ) {
      return null;
    }
    return cursor;
  } catch {
    return null;
  }
}

export function utcDay(date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

export function nextDailyState(
  previousDay: string | null,
  previousStreak: number,
  now = new Date(),
  graceDays = 1,
): { utcDay: string; streak: number; duplicate: boolean; graceUntilUtcDay: string } {
  const today = utcDay(now);
  if (previousDay === today) {
    return {
      utcDay: today,
      streak: previousStreak,
      duplicate: true,
      graceUntilUtcDay: addUtcDays(today, graceDays),
    };
  }
  const yesterday = addUtcDays(today, -1);
  const streak = previousDay === yesterday ? previousStreak + 1 : 1;
  return {
    utcDay: today,
    streak,
    duplicate: false,
    graceUntilUtcDay: addUtcDays(today, graceDays),
  };
}

export function platformMirrorRetryState(
  success: boolean,
  attempts: number,
): { queueStatus: 'synced' | 'failed'; unlockPreserved: true; attempts: number } {
  return {
    queueStatus: success ? 'synced' : 'failed',
    unlockPreserved: true,
    attempts: attempts + 1,
  };
}

export async function competitiveProfile(
  env: CompetitiveEnv,
  player: CompetitivePlayer,
): Promise<Record<string, unknown>> {
  await ensureRatingRows(env, player.id);
  const [globalRating, seasonPeak, showcase, daily] = await Promise.all([
    ratingRow(env, player.id, 'global'),
    seasonPeakRating(env, player.id),
    achievementShowcase(env, player.id),
    dailyRewardState(env, player.id),
  ]);
  const wins = Number(globalRating?.wins ?? player.wins ?? 0);
  const losses = Number(globalRating?.losses ?? player.losses ?? 0);
  const draws = Number(globalRating?.draws ?? 0);
  const gamesPlayed = Number(globalRating?.games_played ?? player.games_played ?? 0);
  const rating = Number(globalRating?.rating ?? player.rating ?? 1000);
  const rank = await leaderboardRank(env, player.id, 'global');
  const achievementCount = await env.DB.prepare(
    'SELECT COUNT(*) AS value FROM player_achievements WHERE player_id = ?',
  )
    .bind(player.id)
    .first<{ value: number }>();

  return {
    publicId: player.public_id,
    username: player.username,
    displayName: player.display_name,
    avatarKey: player.avatar_key,
    country: normalizeCountry(player.country_code),
    currentElo: rating,
    rank,
    rankName: rankName(rating),
    seasonPeak,
    gamesPlayed,
    wins,
    losses,
    draws,
    winRate: winRate(wins, losses, draws),
    winStreak: Number(globalRating?.win_streak ?? 0),
    tournamentEntries: Number(player.tournament_entries ?? 0),
    tournamentPodiums: Number(player.tournament_podiums ?? 0),
    countryContributions: Number(player.country_contributions ?? 0),
    achievementCount: Number(achievementCount?.value ?? player.achievement_count ?? 0),
    achievementShowcase: showcase,
    privateProfile: player.discoverable === 0,
    dailyReward: daily,
  };
}

export async function listAchievements(
  env: CompetitiveEnv,
  playerId: string,
): Promise<Record<string, unknown>> {
  const rows = await env.DB.prepare(
    `SELECT d.id, d.category, d.title, d.description, d.tier, d.reward_amount,
            d.platform_mirror_enabled, pa.unlocked_at, pa.progress,
            pa.platform_mirror_status
     FROM achievement_definitions d
     LEFT JOIN player_achievements pa
       ON pa.achievement_id = d.id AND pa.player_id = ?
     ORDER BY d.sort_order ASC, d.id ASC`,
  )
    .bind(playerId)
    .all<Record<string, unknown>>();
  return {
    categories: ACHIEVEMENT_CATEGORIES,
    achievements: rows.results.map((row) => ({
      id: row.id,
      category: row.category,
      title: row.title,
      description: row.description,
      tier: row.tier,
      rewardAmount: row.reward_amount,
      unlocked: row.unlocked_at != null,
      unlockedAt: row.unlocked_at ?? null,
      progress: row.progress ?? 0,
      platformMirrorEnabled: row.platform_mirror_enabled === 1,
      platformMirrorStatus: row.platform_mirror_status ?? 'not_applicable',
    })),
  };
}

export async function updateAchievementShowcase(
  env: CompetitiveEnv,
  playerId: string,
  achievementIds: string[],
): Promise<Record<string, unknown>> {
  const unique = [...new Set(achievementIds.map((id) => id.trim()).filter(Boolean))];
  if (unique.length > 3) {
    throw new CompetitiveError(400, 'Select at most three achievements.', 'showcase_limit');
  }
  if (unique.length > 0) {
    const placeholders = unique.map(() => '?').join(', ');
    const owned = await env.DB.prepare(
      `SELECT achievement_id FROM player_achievements
       WHERE player_id = ? AND achievement_id IN (${placeholders})`,
    )
      .bind(playerId, ...unique)
      .all<{ achievement_id: string }>();
    if (owned.results.length !== unique.length) {
      throw new CompetitiveError(
        409,
        'Only unlocked achievements can be showcased.',
        'achievement_locked',
      );
    }
  }
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare('DELETE FROM achievement_showcase WHERE player_id = ?').bind(playerId),
    ...unique.map((achievementId, index) =>
      env.DB.prepare(
        `INSERT INTO achievement_showcase (
           player_id, achievement_id, slot, updated_at
         ) VALUES (?, ?, ?, ?)`,
      ).bind(playerId, achievementId, index + 1, now),
    ),
  ]);
  return { achievementShowcase: await achievementShowcase(env, playerId) };
}

export async function unlockAchievement(
  env: CompetitiveEnv,
  input: {
    playerId: string;
    achievementId: string;
    unlockedAt?: string;
  },
): Promise<boolean> {
  const definition = await env.DB.prepare(
    `SELECT id, platform_mirror_enabled FROM achievement_definitions WHERE id = ?`,
  )
    .bind(input.achievementId)
    .first<{ id: string; platform_mirror_enabled: number }>();
  if (!definition) {
    throw new CompetitiveError(404, 'Unknown achievement.', 'achievement_unknown');
  }
  const now = input.unlockedAt ?? new Date().toISOString();
  const status = definition.platform_mirror_enabled === 1 ? 'pending' : 'not_applicable';
  const inserted = await env.DB.prepare(
    `INSERT OR IGNORE INTO player_achievements (
       player_id, achievement_id, unlocked_at, progress, source,
       platform_mirror_status, updated_at
     ) VALUES (?, ?, ?, 100, 'server', ?, ?)`,
  )
    .bind(input.playerId, input.achievementId, now, status, now)
    .run();
  const created = (inserted.meta.changes ?? 0) > 0;
  if (created) {
    await env.DB.prepare(
      `UPDATE players
       SET achievement_count = (
         SELECT COUNT(*) FROM player_achievements WHERE player_id = ?
       ), updated_at = ?
       WHERE id = ?`,
    )
      .bind(input.playerId, now, input.playerId)
      .run();
    if (definition.platform_mirror_enabled === 1) {
      await queuePlatformMirror(env, input.playerId, input.achievementId, now);
    }
  }
  return created;
}

export async function markPlatformMirrorResult(
  env: CompetitiveEnv,
  input: {
    playerId: string;
    achievementId: string;
    platform: 'google_play_games' | 'game_center';
    success: boolean;
    error?: string;
  },
): Promise<void> {
  const now = new Date().toISOString();
  const retry = platformMirrorRetryState(input.success, 0);
  const nextAttemptAt = input.success
    ? now
    : new Date(Date.now() + 60 * 60 * 1000).toISOString();
  await env.DB.prepare(
    `UPDATE platform_achievement_mirror_queue
     SET status = ?, attempts = attempts + 1, next_attempt_at = ?,
         last_error = ?, updated_at = ?
     WHERE player_id = ? AND achievement_id = ? AND platform = ?`,
  )
    .bind(
      retry.queueStatus,
      nextAttemptAt,
      input.success ? null : input.error ?? 'platform_sync_failed',
      now,
      input.playerId,
      input.achievementId,
      input.platform,
    )
    .run();
  await env.DB.prepare(
    `UPDATE player_achievements
     SET platform_mirror_status =
       CASE
         WHEN EXISTS (
           SELECT 1 FROM platform_achievement_mirror_queue
           WHERE player_id = ? AND achievement_id = ? AND status != 'synced'
         ) THEN 'pending'
         ELSE 'synced'
       END,
       updated_at = ?
     WHERE player_id = ? AND achievement_id = ?`,
  )
    .bind(input.playerId, input.achievementId, now, input.playerId, input.achievementId)
    .run();
}

export async function leaderboardPage(
  env: CompetitiveEnv,
  input: {
    scope: string;
    viewerId: string;
    limit: number;
    cursor?: string | null;
    mode?: 'top' | 'around_me' | 'friends';
  },
): Promise<Record<string, unknown>> {
  await ensureRatingRows(env, input.viewerId);
  const limit = Math.max(1, Math.min(100, Math.trunc(input.limit)));
  const cursor = decodeLeaderboardCursor(input.cursor ?? null);
  const mode = input.mode ?? 'top';
  if (mode === 'around_me') {
    return aroundMeLeaderboard(env, input.scope, input.viewerId, limit);
  }
  if (mode === 'friends') {
    return friendsLeaderboard(env, input.scope, input.viewerId, limit);
  }
  const rows = await env.DB.prepare(
    `SELECT pr.*, p.public_id, p.username, p.display_name, p.avatar_key,
            p.country_code
     FROM player_ratings pr
     JOIN players p ON p.id = pr.player_id
     WHERE pr.scope = ?
       AND (
         ? IS NULL
         OR pr.rating < ?
         OR (pr.rating = ? AND pr.games_played < ?)
         OR (pr.rating = ? AND pr.games_played = ? AND pr.wins < ?)
         OR (pr.rating = ? AND pr.games_played = ? AND pr.wins = ? AND pr.draws < ?)
         OR (pr.rating = ? AND pr.games_played = ? AND pr.wins = ? AND pr.draws = ?
             AND pr.updated_at > ?)
         OR (pr.rating = ? AND pr.games_played = ? AND pr.wins = ? AND pr.draws = ?
             AND pr.updated_at = ? AND pr.player_id > ?)
       )
     ORDER BY pr.rating DESC, pr.games_played DESC, pr.wins DESC, pr.draws DESC,
              pr.updated_at ASC, pr.player_id ASC
     LIMIT ?`,
  )
    .bind(
      input.scope,
      cursor?.playerId ?? null,
      cursor?.rating ?? 0,
      cursor?.rating ?? 0,
      cursor?.gamesPlayed ?? 0,
      cursor?.rating ?? 0,
      cursor?.gamesPlayed ?? 0,
      cursor?.wins ?? 0,
      cursor?.rating ?? 0,
      cursor?.gamesPlayed ?? 0,
      cursor?.wins ?? 0,
      cursor?.draws ?? 0,
      cursor?.rating ?? 0,
      cursor?.gamesPlayed ?? 0,
      cursor?.wins ?? 0,
      cursor?.draws ?? 0,
      cursor?.updatedAt ?? '',
      cursor?.rating ?? 0,
      cursor?.gamesPlayed ?? 0,
      cursor?.wins ?? 0,
      cursor?.draws ?? 0,
      cursor?.updatedAt ?? '',
      cursor?.playerId ?? '',
      limit + 1,
    )
    .all<Record<string, unknown>>();
  return leaderboardResponse(env, input.scope, input.viewerId, rows.results, limit, mode);
}

export async function applyDailyRewardState(
  env: CompetitiveEnv,
  playerId: string,
  now = new Date(),
): Promise<{ streak: number; duplicate: boolean; utcDay: string }> {
  const current = await dailyRewardState(env, playerId);
  const next = nextDailyState(
    current.lastClaimUtcDay as string | null,
    Number(current.streak ?? 0),
    now,
  );
  if (!next.duplicate) {
    const stamp = now.toISOString();
    await env.DB.prepare(
      `INSERT INTO daily_reward_state (
         player_id, streak, last_claim_utc_day, grace_until_utc_day, updated_at
       ) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(player_id) DO UPDATE SET
         streak = excluded.streak,
         last_claim_utc_day = excluded.last_claim_utc_day,
         grace_until_utc_day = excluded.grace_until_utc_day,
         updated_at = excluded.updated_at`,
    )
      .bind(playerId, next.streak, next.utcDay, next.graceUntilUtcDay, stamp)
      .run();
    if (next.streak >= 7) {
      await unlockAchievement(env, { playerId, achievementId: 'daily_streak_7', unlockedAt: stamp });
    }
  }
  return { streak: next.streak, duplicate: next.duplicate, utcDay: next.utcDay };
}

async function leaderboardResponse(
  env: CompetitiveEnv,
  scope: string,
  viewerId: string,
  rows: Record<string, unknown>[],
  limit: number,
  mode: string,
): Promise<Record<string, unknown>> {
  const visible = rows.slice(0, limit);
  const next = rows.length > limit ? rows[limit - 1] : null;
  const rankOffset = mode === 'top' ? 0 : 0;
  const version = await leaderboardVersion(env, scope);
  return {
    scope,
    mode,
    snapshotVersion: version.snapshotVersion,
    generatedAt: version.generatedAt,
    stale: version.stale,
    entries: await Promise.all(
      visible.map(async (row, index) => ({
        rank: Number(row.rank ?? index + 1 + rankOffset),
        publicId: row.public_id,
        username: row.username,
        displayName: row.display_name,
        avatarKey: row.avatar_key,
        country: normalizeCountry(row.country_code),
        rating: row.rating,
        gamesPlayed: row.games_played,
        wins: row.wins,
        losses: row.losses,
        draws: row.draws,
        winRate: winRate(Number(row.wins ?? 0), Number(row.losses ?? 0), Number(row.draws ?? 0)),
      })),
    ),
    currentPlayer: {
      rank: await leaderboardRank(env, viewerId, scope),
      rating: Number((await ratingRow(env, viewerId, scope))?.rating ?? 1000),
    },
    nextCursor: next
      ? encodeLeaderboardCursor({
          rating: Number(next.rating),
          gamesPlayed: Number(next.games_played),
          wins: Number(next.wins),
          draws: Number(next.draws),
          updatedAt: String(next.updated_at),
          playerId: String(next.player_id),
        })
      : null,
  };
}

async function aroundMeLeaderboard(
  env: CompetitiveEnv,
  scope: string,
  viewerId: string,
  limit: number,
): Promise<Record<string, unknown>> {
  const rank = await leaderboardRank(env, viewerId, scope);
  const offset = Math.max(0, (rank ?? 1) - Math.ceil(limit / 2));
  const rows = await env.DB.prepare(
    `SELECT ranked.*
     FROM (
       SELECT pr.*, p.public_id, p.username, p.display_name, p.avatar_key,
              p.country_code,
              ROW_NUMBER() OVER (
                ORDER BY pr.rating DESC, pr.games_played DESC, pr.wins DESC,
                         pr.draws DESC, pr.updated_at ASC, pr.player_id ASC
              ) AS rank
       FROM player_ratings pr
       JOIN players p ON p.id = pr.player_id
       WHERE pr.scope = ?
     ) ranked
     WHERE ranked.rank > ?
     ORDER BY ranked.rank ASC
     LIMIT ?`,
  )
    .bind(scope, offset, limit)
    .all<Record<string, unknown>>();
  return leaderboardResponse(env, scope, viewerId, rows.results, limit, 'around_me');
}

async function friendsLeaderboard(
  env: CompetitiveEnv,
  scope: string,
  viewerId: string,
  limit: number,
): Promise<Record<string, unknown>> {
  const rows = await env.DB.prepare(
    `SELECT pr.*, p.public_id, p.username, p.display_name, p.avatar_key,
            p.country_code
     FROM player_ratings pr
     JOIN players p ON p.id = pr.player_id
     WHERE pr.scope = ?
       AND (
         pr.player_id = ?
         OR pr.player_id IN (
           SELECT CASE WHEN f.player_low_id = ? THEN f.player_high_id ELSE f.player_low_id END
           FROM friendships f
           WHERE (f.player_low_id = ? OR f.player_high_id = ?)
             AND f.status = 'accepted'
         )
       )
     ORDER BY pr.rating DESC, pr.games_played DESC, pr.wins DESC, pr.draws DESC,
              pr.updated_at ASC, pr.player_id ASC
     LIMIT ?`,
  )
    .bind(scope, viewerId, viewerId, viewerId, viewerId, limit)
    .all<Record<string, unknown>>();
  return leaderboardResponse(env, scope, viewerId, rows.results, limit, 'friends');
}

async function achievementShowcase(
  env: CompetitiveEnv,
  playerId: string,
): Promise<Record<string, unknown>[]> {
  const rows = await env.DB.prepare(
    `SELECT d.id, d.category, d.title, d.description, d.tier, s.slot
     FROM achievement_showcase s
     JOIN achievement_definitions d ON d.id = s.achievement_id
     WHERE s.player_id = ?
     ORDER BY s.slot ASC`,
  )
    .bind(playerId)
    .all<Record<string, unknown>>();
  return rows.results.map((row) => ({
    id: row.id,
    category: row.category,
    title: row.title,
    description: row.description,
    tier: row.tier,
    slot: row.slot,
  }));
}

async function queuePlatformMirror(
  env: CompetitiveEnv,
  playerId: string,
  achievementId: string,
  now: string,
): Promise<void> {
  await env.DB.batch(
    PLATFORM_MIRROR_PLATFORMS.map((platform) =>
      env.DB.prepare(
        `INSERT OR IGNORE INTO platform_achievement_mirror_queue (
           id, player_id, achievement_id, platform, status, attempts,
           next_attempt_at, created_at, updated_at
         ) VALUES (?, ?, ?, ?, 'pending', 0, ?, ?, ?)`,
      ).bind(crypto.randomUUID(), playerId, achievementId, platform, now, now, now),
    ),
  );
}

async function ensureRatingRows(env: CompetitiveEnv, playerId: string): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO player_ratings (
       player_id, scope, rating, games_played, wins, losses, draws,
       win_streak, best_rating, provisional_games, updated_at
     ) VALUES (?, 'global', 1000, 0, 0, 0, 0, 0, 1000, 20, ?)`,
  )
    .bind(playerId, now)
    .run();
}

async function ratingRow(
  env: CompetitiveEnv,
  playerId: string,
  scope: string,
): Promise<Record<string, unknown> | null> {
  return env.DB.prepare('SELECT * FROM player_ratings WHERE player_id = ? AND scope = ?')
    .bind(playerId, scope)
    .first<Record<string, unknown>>();
}

async function seasonPeakRating(env: CompetitiveEnv, playerId: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT MAX(best_rating) AS value FROM player_ratings WHERE player_id = ?`,
  )
    .bind(playerId)
    .first<{ value: number | null }>();
  return Number(row?.value ?? 1000);
}

async function dailyRewardState(
  env: CompetitiveEnv,
  playerId: string,
): Promise<Record<string, unknown>> {
  const row = await env.DB.prepare(
    'SELECT * FROM daily_reward_state WHERE player_id = ? LIMIT 1',
  )
    .bind(playerId)
    .first<Record<string, unknown>>();
  return {
    streak: Number(row?.streak ?? 0),
    lastClaimUtcDay: row?.last_claim_utc_day ?? null,
    graceUntilUtcDay: row?.grace_until_utc_day ?? null,
  };
}

async function leaderboardRank(
  env: CompetitiveEnv,
  playerId: string,
  scope: string,
): Promise<number | null> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) + 1 AS rank
     FROM player_ratings mine
     JOIN player_ratings other ON other.scope = mine.scope
     WHERE mine.player_id = ? AND mine.scope = ?
       AND (
         other.rating > mine.rating
         OR (other.rating = mine.rating AND other.games_played > mine.games_played)
         OR (other.rating = mine.rating AND other.games_played = mine.games_played
             AND other.wins > mine.wins)
         OR (other.rating = mine.rating AND other.games_played = mine.games_played
             AND other.wins = mine.wins AND other.draws > mine.draws)
         OR (other.rating = mine.rating AND other.games_played = mine.games_played
             AND other.wins = mine.wins AND other.draws = mine.draws
             AND other.updated_at < mine.updated_at)
         OR (other.rating = mine.rating AND other.games_played = mine.games_played
             AND other.wins = mine.wins AND other.draws = mine.draws
             AND other.updated_at = mine.updated_at AND other.player_id < mine.player_id)
       )`,
  )
    .bind(playerId, scope)
    .first<{ rank: number | null }>();
  return row?.rank ?? null;
}

async function leaderboardVersion(
  env: CompetitiveEnv,
  scope: string,
): Promise<{ snapshotVersion: string; generatedAt: string | null; stale: boolean }> {
  const row = await env.DB.prepare(
    `SELECT MAX(updated_at) AS generated_at, COUNT(*) AS count
     FROM player_ratings WHERE scope = ?`,
  )
    .bind(scope)
    .first<{ generated_at: string | null; count: number }>();
  const generatedAt = row?.generated_at ?? null;
  const stale = generatedAt == null || Date.now() - Date.parse(generatedAt) > 5 * 60 * 1000;
  return {
    snapshotVersion: `${scope}:${row?.count ?? 0}:${generatedAt ?? 'empty'}`,
    generatedAt,
    stale,
  };
}

function normalizeCountry(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const country = value.trim().toUpperCase();
  return /^[A-Z]{2}$/.test(country) ? country : null;
}

function addUtcDays(day: string, amount: number): string {
  const date = new Date(`${day}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return utcDay(date);
}
