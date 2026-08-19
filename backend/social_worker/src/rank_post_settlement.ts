import {
  RANK_TIERS,
  encodeIdentityAvatarKey,
  tierByKey,
  tierForPoints,
  type RankProgressionEnv,
} from './rank_progression';

type DerivedProgressionRow = {
  player_id: string;
  rank_points: number;
  highest_rank_points: number;
  ranked_games: number;
  best_win_streak: number;
  best_undefeated_streak: number;
  perfect_wins: number;
  selected_avatar_key: string;
  selected_frame_key: string;
};

/**
 * Reconciles only data derived from an already-settled visible-RP row.
 *
 * This helper deliberately has no access to GameRoom, WebSockets, matchmaking,
 * puzzle state, escrow, match payouts or the authoritative Elo settlement. It
 * exists so a promotion can immediately unlock its lifetime Coin reward,
 * achievement decoration and auto-rank frame even when the player never opens
 * the profile screen after the match.
 */
export async function refreshRankPostSettlement(
  env: RankProgressionEnv,
  playerId: string,
): Promise<void> {
  const progression = await env.DB.prepare(
    `SELECT player_id, rank_points, highest_rank_points, ranked_games,
            best_win_streak, best_undefeated_streak, perfect_wins,
            selected_avatar_key, selected_frame_key
     FROM player_rank_progression
     WHERE player_id = ?
     LIMIT 1`,
  )
    .bind(playerId)
    .first<DerivedProgressionRow>();
  if (!progression) return;

  await Promise.all([
    unlockDerivedAchievements(env, playerId, progression),
    grantReachedRankRewards(env, playerId, progression.highest_rank_points),
  ]);
  await refreshCompositeIdentity(env, playerId, progression);
}

async function unlockDerivedAchievements(
  env: RankProgressionEnv,
  playerId: string,
  progression: DerivedProgressionRow,
): Promise<void> {
  const giant = await env.DB.prepare(
    `SELECT 1 AS value
     FROM rank_progression_settlements
     WHERE player_id = ? AND result = 'win'
       AND opponent_mmr_before - player_mmr_before >= 251
     LIMIT 1`,
  )
    .bind(playerId)
    .first<{ value: number }>();

  const unlocks: string[] = [];
  if (progression.best_undefeated_streak >= 10) unlocks.push('undefeated_10');
  if (progression.best_undefeated_streak >= 25) unlocks.push('undefeated_25');
  if (progression.best_undefeated_streak >= 50) unlocks.push('undefeated_50');
  if (progression.best_win_streak >= 5) unlocks.push('win_streak_5');
  if (progression.best_win_streak >= 10) unlocks.push('win_streak_10');
  if (progression.best_win_streak >= 25) unlocks.push('win_streak_25');
  if (progression.highest_rank_points >= 900) unlocks.push('rank_silver');
  if (progression.highest_rank_points >= 1800) unlocks.push('rank_gold');
  if (progression.highest_rank_points >= 2700) unlocks.push('rank_platinum');
  if (progression.highest_rank_points >= 3600) unlocks.push('rank_master');
  if (progression.highest_rank_points >= 4200) unlocks.push('rank_master_i');
  if (progression.ranked_games >= 100) unlocks.push('ranked_veteran_100');
  if (progression.ranked_games >= 500) unlocks.push('ranked_veteran_500');
  if (progression.ranked_games >= 1000) unlocks.push('ranked_veteran_1000');
  if (progression.perfect_wins >= 1) unlocks.push('perfect_ranked_win');
  if (progression.perfect_wins >= 10) unlocks.push('perfect_ranked_wins_10');
  if (giant) unlocks.push('giant_slayer');
  if (unlocks.length === 0) return;

  const now = new Date().toISOString();
  await env.DB.batch(
    unlocks.map((achievementId) =>
      env.DB.prepare(
        `INSERT OR IGNORE INTO player_achievements (
           player_id, achievement_id, unlocked_at, progress, source,
           platform_mirror_status, updated_at
         )
         SELECT ?, d.id, ?, 100, 'rank_progression', 'not_applicable', ?
         FROM achievement_definitions d
         WHERE d.id = ?`,
      ).bind(playerId, now, now, achievementId),
    ),
  );

  await env.DB.prepare(
    `UPDATE players
     SET achievement_count = (
       SELECT COUNT(*) FROM player_achievements WHERE player_id = ?
     ), updated_at = ?
     WHERE id = ?`,
  )
    .bind(playerId, now, playerId)
    .run();
}

async function grantReachedRankRewards(
  env: RankProgressionEnv,
  playerId: string,
  highestRankPoints: number,
): Promise<void> {
  const reached = RANK_TIERS.filter(
    (tier) => tier.rewardCoins > 0 && tier.minPoints <= highestRankPoints,
  );
  if (reached.length === 0) return;
  const now = new Date().toISOString();
  await env.DB.batch(
    reached.map((tier) =>
      env.DB.prepare(
        `INSERT OR IGNORE INTO rank_reward_grants (
           player_id, rank_key, amount, granted_at
         ) VALUES (?, ?, ?, ?)`,
      ).bind(playerId, tier.key, tier.rewardCoins, now),
    ),
  );
}

async function refreshCompositeIdentity(
  env: RankProgressionEnv,
  playerId: string,
  progression: DerivedProgressionRow,
): Promise<void> {
  const selected = await env.DB.prepare(
    `SELECT c.decoration_key
     FROM achievement_showcase s
     JOIN achievement_cosmetics c ON c.achievement_id = s.achievement_id
     WHERE s.player_id = ?
     ORDER BY s.slot ASC
     LIMIT 3`,
  )
    .bind(playerId)
    .all<{ decoration_key: string }>();

  const currentTier = tierForPoints(progression.rank_points);
  const selectedTier = tierByKey(progression.selected_frame_key);
  const frameKey = progression.selected_frame_key === 'auto'
    ? currentTier.key
    : selectedTier != null &&
        selectedTier.minPoints <= progression.highest_rank_points
      ? selectedTier.key
      : currentTier.key;
  const avatarKey = safeBaseAvatar(progression.selected_avatar_key);
  const composite = encodeIdentityAvatarKey(
    avatarKey,
    frameKey,
    selected.results.map((row) => row.decoration_key),
  );

  await env.DB.prepare(
    `UPDATE players
     SET avatar_key = ?, updated_at = ?
     WHERE id = ? AND avatar_key != ?`,
  )
    .bind(composite, new Date().toISOString(), playerId, composite)
    .run();
}

function safeBaseAvatar(value: string): string {
  const key = String(value || 'default').trim();
  if (key.startsWith('idv1|')) {
    return key.split('|')[1]?.trim() || 'default';
  }
  if (key === 'default') return key;
  if (/^preset_\d{3}$/.test(key)) return key;
  if (/^home-profile-[a-z0-9_-]{1,40}$/i.test(key)) return key;
  return 'default';
}
