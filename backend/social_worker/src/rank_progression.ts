import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';

export type RankProgressionEnv = {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
  ALLOWED_ORIGIN?: string;
};

export type RankResult = 'win' | 'loss' | 'draw';
export type RankLeague = 'bronze' | 'silver' | 'gold' | 'platinum' | 'master';
export type RankDivision = 1 | 2 | 3;

export type RankTier = {
  key: string;
  label: string;
  league: RankLeague;
  division: RankDivision;
  minPoints: number;
  targetMmr: number;
  rewardCoins: number;
};

/**
 * Visible competitive progression.
 *
 * The existing 1000-based Elo stays untouched and is treated as hidden MMR.
 * This table is intentionally independent from matchmaking and online-duel
 * state so cosmetic/rank work cannot change game authority or pairing rules.
 */
export const RANK_TIERS: readonly RankTier[] = Object.freeze([
  { key: 'bronze_3', label: 'Bronze III', league: 'bronze', division: 3, minPoints: 0, targetMmr: 1000, rewardCoins: 0 },
  { key: 'bronze_2', label: 'Bronze II', league: 'bronze', division: 2, minPoints: 300, targetMmr: 1100, rewardCoins: 250 },
  { key: 'bronze_1', label: 'Bronze I', league: 'bronze', division: 1, minPoints: 600, targetMmr: 1200, rewardCoins: 350 },
  { key: 'silver_3', label: 'Silver III', league: 'silver', division: 3, minPoints: 900, targetMmr: 1300, rewardCoins: 600 },
  { key: 'silver_2', label: 'Silver II', league: 'silver', division: 2, minPoints: 1200, targetMmr: 1400, rewardCoins: 450 },
  { key: 'silver_1', label: 'Silver I', league: 'silver', division: 1, minPoints: 1500, targetMmr: 1500, rewardCoins: 550 },
  { key: 'gold_3', label: 'Gold III', league: 'gold', division: 3, minPoints: 1800, targetMmr: 1600, rewardCoins: 900 },
  { key: 'gold_2', label: 'Gold II', league: 'gold', division: 2, minPoints: 2100, targetMmr: 1700, rewardCoins: 650 },
  { key: 'gold_1', label: 'Gold I', league: 'gold', division: 1, minPoints: 2400, targetMmr: 1800, rewardCoins: 750 },
  { key: 'platinum_3', label: 'Platinum III', league: 'platinum', division: 3, minPoints: 2700, targetMmr: 1900, rewardCoins: 1200 },
  { key: 'platinum_2', label: 'Platinum II', league: 'platinum', division: 2, minPoints: 3000, targetMmr: 2000, rewardCoins: 850 },
  { key: 'platinum_1', label: 'Platinum I', league: 'platinum', division: 1, minPoints: 3300, targetMmr: 2100, rewardCoins: 950 },
  { key: 'master_3', label: 'Master III', league: 'master', division: 3, minPoints: 3600, targetMmr: 2200, rewardCoins: 1500 },
  { key: 'master_2', label: 'Master II', league: 'master', division: 2, minPoints: 3900, targetMmr: 2300, rewardCoins: 1200 },
  { key: 'master_1', label: 'Master I', league: 'master', division: 1, minPoints: 4200, targetMmr: 2400, rewardCoins: 1800 },
]);

export const TOTAL_LIFETIME_RANK_REWARD = RANK_TIERS.reduce(
  (sum, tier) => sum + tier.rewardCoins,
  0,
);

const RANK_SYSTEM_EPOCH = '2026-08-19T13:45:00.000Z';
const MAX_RECONCILE_BATCH = 100;
const MAX_RECONCILE_PASSES = 5;
const REPEAT_WINDOW_MS = 24 * 60 * 60 * 1000;
const ABANDONMENT_PENALTY = 8;
const MAX_PRESET_AVATARS = 96;

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);

const ABANDONMENT_REASONS = new Set([
  'explicit_forfeit',
  'disconnect_forfeit',
  'consecutive_timeouts',
]);

const TITLE_UNLOCKS = [
  { key: 'master', label: 'Master', minPoints: 3600 },
  { key: 'master_i', label: 'Master I', minPoints: 4200 },
] as const;

export class RankProgressionError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

type PlayerRow = {
  id: string;
  firebase_uid: string;
  public_id: string;
  username: string;
  display_name: string;
  avatar_key: string;
  created_at: string;
  online_coins: number;
};

type ProgressionRow = {
  player_id: string;
  rank_points: number;
  highest_rank_points: number;
  ranked_games: number;
  ranked_wins: number;
  ranked_losses: number;
  ranked_draws: number;
  win_streak: number;
  best_win_streak: number;
  undefeated_streak: number;
  best_undefeated_streak: number;
  perfect_wins: number;
  selected_avatar_key: string;
  selected_frame_key: string;
  selected_title_key: string;
  started_at: string;
  updated_at: string;
};

type PendingMatch = {
  match_id: string;
  opponent_id: string;
  finished_at: string;
  finish_reason: string | null;
  result: RankResult;
  mistakes: number;
  timeouts: number;
  player_mmr_before: number;
  opponent_mmr_before: number;
};

type DecorationRow = {
  achievement_id: string;
  decoration_key: string;
  rarity: string;
  title: string;
  description: string;
  tier: string;
  unlocked_at: string | null;
  slot: number | null;
  sort_order: number;
};

export function isRankProgressionRoute(pathname: string): boolean {
  return (
    pathname === '/v1/me/rank-profile' ||
    pathname === '/v1/competitive/rank-leaderboard'
  );
}

export async function handleRankProgressionRequest(
  request: Request,
  env: RankProgressionEnv,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    const player = await playerForUid(env, uid);
    if (!player) {
      throw new RankProgressionError(
        404,
        'Player profile not found. Open the online profile once and try again.',
        'player_not_found',
      );
    }

    const url = new URL(request.url);
    if (url.pathname === '/v1/me/rank-profile') {
      if (request.method === 'GET') {
        return json(env, 200, await rankProfile(env, player));
      }
      if (request.method === 'PUT') {
        const body = await readJson(request);
        await reconcileRankProgression(env, player.id);
        await updateIdentitySelection(env, player, body);
        const refreshed = await playerById(env, player.id);
        return json(env, 200, await rankProfile(env, refreshed ?? player));
      }
      return json(env, 405, {
        error: 'Method not allowed.',
        code: 'method_not_allowed',
      });
    }

    if (
      url.pathname === '/v1/competitive/rank-leaderboard' &&
      request.method === 'GET'
    ) {
      await reconcileRankProgression(env, player.id);
      const rawLimit = Number(url.searchParams.get('limit') ?? '50');
      const limit = Number.isFinite(rawLimit)
        ? Math.max(1, Math.min(100, Math.trunc(rawLimit)))
        : 50;
      return json(env, 200, await rankLeaderboard(env, player.id, limit));
    }

    return json(env, 405, {
      error: 'Method not allowed.',
      code: 'method_not_allowed',
    });
  } catch (error) {
    if (error instanceof AppCheckError) {
      return json(env, 403, { error: error.message, code: error.code });
    }
    if (error instanceof RankProgressionError) {
      return json(env, error.status, { error: error.message, code: error.code });
    }
    console.error('rank_progression_route_failed', error);
    return json(env, 500, {
      error: 'Rank progression is temporarily unavailable.',
      code: 'rank_progression_failed',
    });
  }
}

/** Base visible-RP result based only on the hidden-MMR difference and result. */
export function baseRankDelta(
  playerMmr: number,
  opponentMmr: number,
  result: RankResult,
): number {
  const difference = opponentMmr - playerMmr;
  if (difference <= -251) return result === 'win' ? 10 : result === 'draw' ? -15 : -40;
  if (difference <= -151) return result === 'win' ? 12 : result === 'draw' ? -12 : -36;
  if (difference <= -76) return result === 'win' ? 18 : result === 'draw' ? -6 : -30;
  if (difference <= 75) return result === 'win' ? 24 : result === 'draw' ? 0 : -24;
  if (difference <= 150) return result === 'win' ? 30 : result === 'draw' ? 6 : -18;
  if (difference <= 250) return result === 'win' ? 36 : result === 'draw' ? 12 : -12;
  return result === 'win' ? 40 : result === 'draw' ? 15 : -10;
}

/**
 * Catch-up / correction modifier between hidden MMR and visible rank.
 * Positive percentages describe the magnitude applied to the base delta.
 */
export function rankAlignmentPercent(
  delta: number,
  playerMmr: number,
  rankTargetMmr: number,
): number {
  if (delta === 0) return 100;
  const difference = playerMmr - rankTargetMmr;

  if (difference >= 200) return delta > 0 ? 125 : 75;
  if (difference >= 100) return delta > 0 ? 110 : 90;
  if (difference <= -200) return delta > 0 ? 75 : 125;
  if (difference <= -100) return delta > 0 ? 90 : 110;
  return 100;
}

export function applyPercent(delta: number, percent: number): number {
  return Math.round((delta * percent) / 100);
}

/**
 * Anti-farm repeat scaling. It is applied to positive gains only so a player
 * cannot repeatedly queue the same opponent to make future losses harmless.
 */
export function repeatGainPercent(priorMatchesIn24Hours: number): number {
  if (priorMatchesIn24Hours <= 1) return 100;
  if (priorMatchesIn24Hours === 2) return 50;
  return 0;
}

export function tierForPoints(points: number): RankTier {
  const safe = Math.max(0, Math.trunc(points));
  for (let index = RANK_TIERS.length - 1; index >= 0; index--) {
    if (safe >= RANK_TIERS[index].minPoints) return RANK_TIERS[index];
  }
  return RANK_TIERS[0];
}

export function tierByKey(key: string): RankTier | null {
  return RANK_TIERS.find((tier) => tier.key === key) ?? null;
}

export function nextTierForPoints(points: number): RankTier | null {
  const current = tierForPoints(points);
  const index = RANK_TIERS.findIndex((tier) => tier.key === current.key);
  return index >= 0 && index < RANK_TIERS.length - 1
    ? RANK_TIERS[index + 1]
    : null;
}

export function pointsProgress(points: number): {
  pointsInDivision: number;
  divisionSize: number | null;
  pointsToNext: number | null;
  progress: number;
} {
  const current = tierForPoints(points);
  const next = nextTierForPoints(points);
  if (!next) {
    return {
      pointsInDivision: Math.max(0, points - current.minPoints),
      divisionSize: null,
      pointsToNext: null,
      progress: 1,
    };
  }
  const divisionSize = next.minPoints - current.minPoints;
  const pointsInDivision = Math.max(0, points - current.minPoints);
  return {
    pointsInDivision,
    divisionSize,
    pointsToNext: Math.max(0, next.minPoints - points),
    progress: Math.max(0, Math.min(1, pointsInDivision / divisionSize)),
  };
}

async function rankProfile(
  env: RankProgressionEnv,
  player: PlayerRow,
): Promise<Record<string, unknown>> {
  const reconciliation = await reconcileRankProgression(env, player.id);
  const progression = reconciliation.progression;
  await reconcileMilestoneAchievements(env, player.id, progression);
  await reconcileRankRewards(env, player.id, progression.highest_rank_points);
  await refreshCompositeAvatar(env, player.id, progression);

  const currentPlayer = await playerById(env, player.id);
  const current = tierForPoints(progression.rank_points);
  const next = nextTierForPoints(progression.rank_points);
  const highest = tierForPoints(progression.highest_rank_points);
  const progress = pointsProgress(progression.rank_points);
  const decorations = await decorationCatalog(env, player.id);
  const rewards = await rankRewardStates(env, player.id);
  const selectedDecorationIds = decorations
    .filter((item) => item.slot != null)
    .sort((a, b) => Number(a.slot) - Number(b.slot))
    .map((item) => item.achievement_id);
  const selectedDecorationKeys = decorations
    .filter((item) => item.slot != null)
    .sort((a, b) => Number(a.slot) - Number(b.slot))
    .map((item) => item.decoration_key);
  const effectiveFrame = effectiveFrameKey(progression);
  const unlockedFrames = RANK_TIERS
    .filter((tier) => tier.minPoints <= progression.highest_rank_points)
    .map((tier) => tier.key);
  const unlockedTitles = TITLE_UNLOCKS
    .filter((title) => title.minPoints <= progression.highest_rank_points)
    .map((title) => ({ key: title.key, label: title.label }));
  const selectedTitle = TITLE_UNLOCKS.some(
    (title) => title.key === progression.selected_title_key &&
      title.minPoints <= progression.highest_rank_points,
  )
    ? progression.selected_title_key
    : '';

  return {
    publicId: player.public_id,
    username: player.username,
    displayName: player.display_name,
    avatarKey: currentPlayer?.avatar_key ?? player.avatar_key,
    selectedAvatarKey: progression.selected_avatar_key,
    selectedFrameKey: progression.selected_frame_key,
    effectiveFrameKey: effectiveFrame,
    selectedTitleKey: selectedTitle,
    unlockedTitles,
    selectedDecorationAchievementIds: selectedDecorationIds,
    selectedDecorationKeys,
    rankPoints: progression.rank_points,
    highestRankPoints: progression.highest_rank_points,
    rankKey: current.key,
    rankName: current.label,
    league: current.league,
    division: current.division,
    nextRankKey: next?.key ?? null,
    nextRankName: next?.label ?? null,
    highestRankKey: highest.key,
    highestRankName: highest.label,
    ...progress,
    unlockedFrameKeys: unlockedFrames,
    availableAvatarCount: MAX_PRESET_AVATARS,
    decorations: decorations.map(decorationJson),
    rankRewards: rewards,
    totalLifetimeRankReward: TOTAL_LIFETIME_RANK_REWARD,
    stats: {
      rankedGames: progression.ranked_games,
      wins: progression.ranked_wins,
      losses: progression.ranked_losses,
      draws: progression.ranked_draws,
      winStreak: progression.win_streak,
      bestWinStreak: progression.best_win_streak,
      undefeatedStreak: progression.undefeated_streak,
      bestUndefeatedStreak: progression.best_undefeated_streak,
      perfectWins: progression.perfect_wins,
    },
    processedMatches: reconciliation.processedMatches,
    reconciliationPending: reconciliation.pending,
  };
}

export async function reconcileRankProgression(
  env: RankProgressionEnv,
  playerId: string,
): Promise<{
  progression: ProgressionRow;
  processedMatches: number;
  pending: boolean;
}> {
  await ensureProgressionRow(env, playerId);
  let processedMatches = 0;
  let pending = false;

  for (let pass = 0; pass < MAX_RECONCILE_PASSES; pass++) {
    const progression = await progressionFor(env, playerId);
    if (!progression) {
      throw new RankProgressionError(500, 'Unable to initialize rank progression.', 'rank_state_missing');
    }
    const matches = await pendingRankMatches(
      env,
      playerId,
      progression.started_at,
      MAX_RECONCILE_BATCH,
    );
    if (matches.length === 0) {
      pending = false;
      break;
    }

    for (const match of matches) {
      const fresh = await progressionFor(env, playerId);
      if (!fresh) break;
      const applied = await settleVisibleRankMatch(env, fresh, match);
      if (applied) processedMatches++;
    }

    if (matches.length < MAX_RECONCILE_BATCH) {
      pending = false;
      break;
    }
    pending = true;
  }

  const final = await progressionFor(env, playerId);
  if (!final) {
    throw new RankProgressionError(500, 'Unable to load rank progression.', 'rank_state_missing');
  }
  return { progression: final, processedMatches, pending };
}

async function settleVisibleRankMatch(
  env: RankProgressionEnv,
  progression: ProgressionRow,
  match: PendingMatch,
): Promise<boolean> {
  const beforePoints = Number(progression.rank_points);
  const beforeTier = tierForPoints(beforePoints);
  const playerMmr = Number(match.player_mmr_before ?? 1000);
  const opponentMmr = Number(match.opponent_mmr_before ?? 1000);
  const base = baseRankDelta(playerMmr, opponentMmr, match.result);
  const alignmentPercent = rankAlignmentPercent(
    base,
    playerMmr,
    beforeTier.targetMmr,
  );
  const aligned = applyPercent(base, alignmentPercent);
  const priorMatches = await recentPairMatchCount(
    env,
    progression.player_id,
    match.opponent_id,
    match.finished_at,
  );
  const repeatPercent = repeatGainPercent(priorMatches);
  // Repeat protection never softens a loss. It only reduces positive farming.
  const repeatAdjusted = aligned > 0
    ? applyPercent(aligned, repeatPercent)
    : aligned;
  const abandonmentPenalty =
    match.result === 'loss' && ABANDONMENT_REASONS.has(match.finish_reason ?? '')
      ? ABANDONMENT_PENALTY
      : 0;
  const requestedDelta = repeatAdjusted - abandonmentPenalty;
  const afterPoints = Math.max(0, beforePoints + requestedDelta);
  const actualDelta = afterPoints - beforePoints;
  const afterTier = tierForPoints(afterPoints);

  const isWin = match.result === 'win';
  const isLoss = match.result === 'loss';
  const isDraw = match.result === 'draw';
  const nextWinStreak = isWin ? progression.win_streak + 1 : 0;
  const nextUndefeated = isLoss ? 0 : progression.undefeated_streak + 1;
  const perfectWin =
    isWin && Number(match.mistakes ?? 0) === 0 && Number(match.timeouts ?? 0) === 0;
  const now = new Date().toISOString();
  const token = crypto.randomUUID();
  const nextHighest = Math.max(progression.highest_rank_points, afterPoints);

  const results = await env.DB.batch([
    env.DB.prepare(
      `INSERT OR IGNORE INTO rank_progression_settlements (
         match_id, player_id, opponent_id, settlement_token, finished_at,
         result, finish_reason, player_mmr_before, opponent_mmr_before,
         base_delta, alignment_percent, repeat_percent, abandonment_penalty,
         rp_delta, rp_before, rp_after, rank_before, rank_after, created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      match.match_id,
      progression.player_id,
      match.opponent_id,
      token,
      match.finished_at,
      match.result,
      match.finish_reason,
      playerMmr,
      opponentMmr,
      base,
      alignmentPercent,
      repeatPercent,
      abandonmentPenalty,
      actualDelta,
      beforePoints,
      afterPoints,
      beforeTier.key,
      afterTier.key,
      now,
    ),
    env.DB.prepare(
      `UPDATE player_rank_progression
       SET rank_points = ?,
           highest_rank_points = ?,
           ranked_games = ranked_games + 1,
           ranked_wins = ranked_wins + ?,
           ranked_losses = ranked_losses + ?,
           ranked_draws = ranked_draws + ?,
           win_streak = ?,
           best_win_streak = MAX(best_win_streak, ?),
           undefeated_streak = ?,
           best_undefeated_streak = MAX(best_undefeated_streak, ?),
           perfect_wins = perfect_wins + ?,
           updated_at = ?
       WHERE player_id = ?
         AND EXISTS (
           SELECT 1 FROM rank_progression_settlements s
           WHERE s.match_id = ? AND s.player_id = ? AND s.settlement_token = ?
         )`,
    ).bind(
      afterPoints,
      nextHighest,
      isWin ? 1 : 0,
      isLoss ? 1 : 0,
      isDraw ? 1 : 0,
      nextWinStreak,
      nextWinStreak,
      nextUndefeated,
      nextUndefeated,
      perfectWin ? 1 : 0,
      now,
      progression.player_id,
      match.match_id,
      progression.player_id,
      token,
    ),
  ]);

  return Number(results[1]?.meta?.changes ?? 0) > 0;
}

async function reconcileMilestoneAchievements(
  env: RankProgressionEnv,
  playerId: string,
  progression: ProgressionRow,
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

async function reconcileRankRewards(
  env: RankProgressionEnv,
  playerId: string,
  highestPoints: number,
): Promise<void> {
  const eligible = RANK_TIERS.filter(
    (tier) => tier.rewardCoins > 0 && tier.minPoints <= highestPoints,
  );
  if (eligible.length === 0) return;
  const now = new Date().toISOString();
  await env.DB.batch(
    eligible.map((tier) =>
      env.DB.prepare(
        `INSERT OR IGNORE INTO rank_reward_grants (
           player_id, rank_key, amount, granted_at
         ) VALUES (?, ?, ?, ?)`,
      ).bind(playerId, tier.key, tier.rewardCoins, now),
    ),
  );
}

async function updateIdentitySelection(
  env: RankProgressionEnv,
  player: PlayerRow,
  body: Record<string, unknown>,
): Promise<void> {
  const progression = await progressionFor(env, player.id);
  if (!progression) {
    throw new RankProgressionError(500, 'Rank profile is not initialized.', 'rank_state_missing');
  }

  const avatarKey = body.avatarKey == null
    ? progression.selected_avatar_key
    : validateAvatarKey(String(body.avatarKey));
  const requestedFrame = body.frameKey == null
    ? progression.selected_frame_key
    : String(body.frameKey).trim().toLowerCase();
  validateFrameKey(requestedFrame, progression.highest_rank_points);

  const requestedTitle = body.titleKey == null
    ? progression.selected_title_key
    : String(body.titleKey).trim().toLowerCase();
  validateTitleKey(requestedTitle, progression.highest_rank_points);

  let selectedAchievements: string[] | null = null;
  if (body.achievementIds != null) {
    if (!Array.isArray(body.achievementIds)) {
      throw new RankProgressionError(400, 'achievementIds must be a list.', 'invalid_decorations');
    }
    selectedAchievements = [
      ...new Set(
        body.achievementIds
          .map((value) => String(value).trim())
          .filter(Boolean),
      ),
    ];
    if (selectedAchievements.length > 3) {
      throw new RankProgressionError(400, 'Select at most three frame decorations.', 'decoration_limit');
    }
    await assertDecorationsUnlocked(env, player.id, selectedAchievements);
  }

  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE player_rank_progression
     SET selected_avatar_key = ?, selected_frame_key = ?, selected_title_key = ?, updated_at = ?
     WHERE player_id = ?`,
  )
    .bind(avatarKey, requestedFrame, requestedTitle, now, player.id)
    .run();

  if (selectedAchievements != null) {
    const statements: D1PreparedStatement[] = [
      env.DB.prepare('DELETE FROM achievement_showcase WHERE player_id = ?').bind(player.id),
    ];
    selectedAchievements.forEach((achievementId, index) => {
      statements.push(
        env.DB.prepare(
          `INSERT INTO achievement_showcase (
             player_id, achievement_id, slot, updated_at
           ) VALUES (?, ?, ?, ?)`,
        ).bind(player.id, achievementId, index + 1, now),
      );
    });
    await env.DB.batch(statements);
  }

  const updated = await progressionFor(env, player.id);
  if (updated) await refreshCompositeAvatar(env, player.id, updated);
}

async function assertDecorationsUnlocked(
  env: RankProgressionEnv,
  playerId: string,
  achievementIds: string[],
): Promise<void> {
  if (achievementIds.length === 0) return;
  const placeholders = achievementIds.map(() => '?').join(', ');
  const rows = await env.DB.prepare(
    `SELECT pa.achievement_id
     FROM player_achievements pa
     JOIN achievement_cosmetics c ON c.achievement_id = pa.achievement_id
     WHERE pa.player_id = ? AND pa.achievement_id IN (${placeholders})`,
  )
    .bind(playerId, ...achievementIds)
    .all<{ achievement_id: string }>();
  if (rows.results.length !== achievementIds.length) {
    throw new RankProgressionError(
      409,
      'Only unlocked achievements with a frame decoration can be equipped.',
      'decoration_locked',
    );
  }
}

function validateAvatarKey(value: string): string {
  const key = value.trim();
  if (key === 'default') return key;
  if (/^preset_(\d{3})$/.test(key)) {
    const index = Number(key.slice('preset_'.length));
    if (index >= 1 && index <= MAX_PRESET_AVATARS) return key;
  }
  // Local platform-avatar presentation remains supported. It is never copied
  // into backend image storage; other players safely fall back to initials.
  if (/^home-profile-[a-z0-9_-]{1,40}$/i.test(key)) return key;
  throw new RankProgressionError(400, 'Invalid avatar selection.', 'invalid_avatar');
}

function validateFrameKey(key: string, highestPoints: number): void {
  if (key === 'auto') return;
  const tier = tierByKey(key);
  if (!tier) {
    throw new RankProgressionError(400, 'Unknown rank frame.', 'invalid_frame');
  }
  if (tier.minPoints > highestPoints) {
    throw new RankProgressionError(409, 'This rank frame has not been unlocked yet.', 'frame_locked');
  }
}

function validateTitleKey(key: string, highestPoints: number): void {
  if (key === '') return;
  const title = TITLE_UNLOCKS.find((item) => item.key === key);
  if (!title) {
    throw new RankProgressionError(400, 'Unknown title.', 'invalid_title');
  }
  if (title.minPoints > highestPoints) {
    throw new RankProgressionError(409, 'This title has not been unlocked yet.', 'title_locked');
  }
}

async function refreshCompositeAvatar(
  env: RankProgressionEnv,
  playerId: string,
  progression: ProgressionRow,
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
  const base = safeExistingAvatarBase(progression.selected_avatar_key);
  const frame = effectiveFrameKey(progression);
  const composite = encodeIdentityAvatarKey(
    base,
    frame,
    selected.results.map((row) => row.decoration_key),
  );
  await env.DB.prepare(
    `UPDATE players SET avatar_key = ?, updated_at = ?
     WHERE id = ? AND avatar_key != ?`,
  )
    .bind(composite, new Date().toISOString(), playerId, composite)
    .run();
}

export function encodeIdentityAvatarKey(
  avatarKey: string,
  frameKey: string,
  decorationKeys: string[],
): string {
  const safeAvatar = avatarKey.replace(/[|,]/g, '');
  const safeFrame = frameKey.replace(/[|,]/g, '');
  const safeDecorations = decorationKeys
    .slice(0, 3)
    .map((key) => key.replace(/[|,]/g, ''))
    .filter(Boolean)
    .join(',');
  return `idv1|${safeAvatar}|${safeFrame}|${safeDecorations}`;
}

function safeExistingAvatarBase(value: string): string {
  const key = String(value || 'default').trim();
  if (key.startsWith('idv1|')) {
    return key.split('|')[1]?.trim() || 'default';
  }
  if (key === 'default') return key;
  if (/^preset_\d{3}$/.test(key)) return key;
  if (/^home-profile-[a-z0-9_-]{1,40}$/i.test(key)) return key;
  return 'default';
}

function effectiveFrameKey(progression: ProgressionRow): string {
  if (progression.selected_frame_key === 'auto') {
    return tierForPoints(progression.rank_points).key;
  }
  const selected = tierByKey(progression.selected_frame_key);
  if (!selected || selected.minPoints > progression.highest_rank_points) {
    return tierForPoints(progression.rank_points).key;
  }
  return selected.key;
}

async function rankLeaderboard(
  env: RankProgressionEnv,
  viewerId: string,
  limit: number,
): Promise<Record<string, unknown>> {
  const rows = await env.DB.prepare(
    `SELECT rp.rank_points, rp.highest_rank_points, rp.ranked_games,
            rp.ranked_wins, rp.ranked_losses, rp.ranked_draws,
            p.id AS player_id, p.public_id, p.username, p.display_name, p.avatar_key
     FROM player_rank_progression rp
     JOIN players p ON p.id = rp.player_id
     WHERE rp.ranked_games > 0
     ORDER BY rp.rank_points DESC, rp.ranked_games DESC, rp.updated_at ASC, rp.player_id ASC
     LIMIT ?`,
  )
    .bind(limit)
    .all<Record<string, unknown>>();

  const viewerRank = await env.DB.prepare(
    `SELECT COUNT(*) + 1 AS value
     FROM player_rank_progression mine
     JOIN player_rank_progression other
       ON other.rank_points > mine.rank_points
       OR (other.rank_points = mine.rank_points AND other.ranked_games > mine.ranked_games)
       OR (other.rank_points = mine.rank_points AND other.ranked_games = mine.ranked_games
           AND other.updated_at < mine.updated_at)
       OR (other.rank_points = mine.rank_points AND other.ranked_games = mine.ranked_games
           AND other.updated_at = mine.updated_at AND other.player_id < mine.player_id)
     WHERE mine.player_id = ?`,
  )
    .bind(viewerId)
    .first<{ value: number }>();
  const viewer = await progressionFor(env, viewerId);

  return {
    entries: rows.results.map((row, index) => {
      const points = Number(row.rank_points ?? 0);
      const tier = tierForPoints(points);
      const games = Number(row.ranked_games ?? 0);
      const wins = Number(row.ranked_wins ?? 0);
      return {
        rank: index + 1,
        publicId: row.public_id,
        username: row.username,
        displayName: row.display_name,
        avatarKey: row.avatar_key,
        rankPoints: points,
        rankKey: tier.key,
        rankName: tier.label,
        gamesPlayed: games,
        wins,
        losses: Number(row.ranked_losses ?? 0),
        draws: Number(row.ranked_draws ?? 0),
        winRate: games === 0 ? 0 : wins / games,
      };
    }),
    currentPlayer: viewer
      ? {
          rank: Number(viewerRank?.value ?? 1),
          rankPoints: viewer.rank_points,
          rankKey: tierForPoints(viewer.rank_points).key,
          rankName: tierForPoints(viewer.rank_points).label,
        }
      : null,
  };
}

async function rankRewardStates(
  env: RankProgressionEnv,
  playerId: string,
): Promise<Record<string, unknown>[]> {
  const rows = await env.DB.prepare(
    `SELECT rank_key, amount, granted_at
     FROM rank_reward_grants WHERE player_id = ?`,
  )
    .bind(playerId)
    .all<{ rank_key: string; amount: number; granted_at: string }>();
  const claimed = new Map(rows.results.map((row) => [row.rank_key, row]));
  return RANK_TIERS
    .filter((tier) => tier.rewardCoins > 0)
    .map((tier) => ({
      rankKey: tier.key,
      rankName: tier.label,
      requiredPoints: tier.minPoints,
      amount: tier.rewardCoins,
      claimed: claimed.has(tier.key),
      claimedAt: claimed.get(tier.key)?.granted_at ?? null,
    }));
}

async function decorationCatalog(
  env: RankProgressionEnv,
  playerId: string,
): Promise<DecorationRow[]> {
  const rows = await env.DB.prepare(
    `SELECT c.achievement_id, c.decoration_key, c.rarity, c.sort_order,
            d.title, d.description, d.tier,
            pa.unlocked_at, s.slot
     FROM achievement_cosmetics c
     JOIN achievement_definitions d ON d.id = c.achievement_id
     LEFT JOIN player_achievements pa
       ON pa.achievement_id = c.achievement_id AND pa.player_id = ?
     LEFT JOIN achievement_showcase s
       ON s.achievement_id = c.achievement_id AND s.player_id = ?
     ORDER BY CASE WHEN pa.unlocked_at IS NULL THEN 1 ELSE 0 END,
              CASE WHEN s.slot IS NULL THEN 1 ELSE 0 END,
              c.sort_order ASC`,
  )
    .bind(playerId, playerId)
    .all<DecorationRow>();
  return rows.results;
}

function decorationJson(row: DecorationRow): Record<string, unknown> {
  return {
    achievementId: row.achievement_id,
    decorationKey: row.decoration_key,
    rarity: row.rarity,
    title: row.title,
    description: row.description,
    tier: row.tier,
    unlocked: row.unlocked_at != null,
    unlockedAt: row.unlocked_at ?? null,
    selected: row.slot != null,
    slot: row.slot ?? null,
  };
}

async function pendingRankMatches(
  env: RankProgressionEnv,
  playerId: string,
  startedAt: string,
  limit: number,
): Promise<PendingMatch[]> {
  const rows = await env.DB.prepare(
    `SELECT mp.match_id,
            opponent.player_id AS opponent_id,
            m.finished_at,
            m.finish_reason,
            mp.result,
            COALESCE(mp.mistakes, 0) AS mistakes,
            COALESCE(mp.timeouts, 0) AS timeouts,
            COALESCE(mp.rating_before_global, 1000) AS player_mmr_before,
            COALESCE(opponent.rating_before_global, 1000) AS opponent_mmr_before
     FROM match_players mp
     JOIN matches m ON m.id = mp.match_id
     JOIN match_players opponent
       ON opponent.match_id = mp.match_id AND opponent.player_id != mp.player_id
     LEFT JOIN rank_progression_settlements settled
       ON settled.match_id = mp.match_id AND settled.player_id = mp.player_id
     WHERE mp.player_id = ?
       AND m.rated = 1
       AND m.finished_at IS NOT NULL
       AND m.finished_at >= ?
       AND mp.result IN ('win', 'loss', 'draw')
       AND settled.match_id IS NULL
     ORDER BY m.finished_at ASC, mp.match_id ASC
     LIMIT ?`,
  )
    .bind(playerId, startedAt, limit)
    .all<Record<string, unknown>>();

  return rows.results.map((row) => ({
    match_id: String(row.match_id),
    opponent_id: String(row.opponent_id),
    finished_at: String(row.finished_at),
    finish_reason: row.finish_reason == null ? null : String(row.finish_reason),
    result: String(row.result) as RankResult,
    mistakes: Number(row.mistakes ?? 0),
    timeouts: Number(row.timeouts ?? 0),
    player_mmr_before: Number(row.player_mmr_before ?? 1000),
    opponent_mmr_before: Number(row.opponent_mmr_before ?? 1000),
  }));
}

async function recentPairMatchCount(
  env: RankProgressionEnv,
  playerId: string,
  opponentId: string,
  currentFinishedAt: string,
): Promise<number> {
  const currentMs = Date.parse(currentFinishedAt);
  const from = Number.isFinite(currentMs)
    ? new Date(currentMs - REPEAT_WINDOW_MS).toISOString()
    : new Date(Date.now() - REPEAT_WINDOW_MS).toISOString();
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS value
     FROM rank_progression_settlements
     WHERE player_id = ? AND opponent_id = ?
       AND finished_at >= ? AND finished_at < ?`,
  )
    .bind(playerId, opponentId, from, currentFinishedAt)
    .first<{ value: number }>();
  return Number(row?.value ?? 0);
}

async function ensureProgressionRow(
  env: RankProgressionEnv,
  playerId: string,
): Promise<void> {
  const player = await playerById(env, playerId);
  if (!player) {
    throw new RankProgressionError(404, 'Player profile not found.', 'player_not_found');
  }
  const startedAt = player.created_at > RANK_SYSTEM_EPOCH
    ? player.created_at
    : RANK_SYSTEM_EPOCH;
  const baseAvatar = safeExistingAvatarBase(player.avatar_key);
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO player_rank_progression (
       player_id, rank_points, highest_rank_points,
       selected_avatar_key, selected_frame_key, selected_title_key,
       started_at, updated_at
     ) VALUES (?, 0, 0, ?, 'auto', '', ?, ?)`,
  )
    .bind(playerId, baseAvatar, startedAt, now)
    .run();
}

async function progressionFor(
  env: RankProgressionEnv,
  playerId: string,
): Promise<ProgressionRow | null> {
  return env.DB.prepare(
    'SELECT * FROM player_rank_progression WHERE player_id = ? LIMIT 1',
  )
    .bind(playerId)
    .first<ProgressionRow>();
}

async function playerForUid(
  env: RankProgressionEnv,
  uid: string,
): Promise<PlayerRow | null> {
  return env.DB.prepare(
    `SELECT id, firebase_uid, public_id, username, display_name, avatar_key,
            created_at, online_coins
     FROM players WHERE firebase_uid = ? LIMIT 1`,
  )
    .bind(uid)
    .first<PlayerRow>();
}

async function playerById(
  env: RankProgressionEnv,
  playerId: string,
): Promise<PlayerRow | null> {
  return env.DB.prepare(
    `SELECT id, firebase_uid, public_id, username, display_name, avatar_key,
            created_at, online_coins
     FROM players WHERE id = ? LIMIT 1`,
  )
    .bind(playerId)
    .first<PlayerRow>();
}

async function authenticateFirebase(
  request: Request,
  env: RankProgressionEnv,
): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new RankProgressionError(401, 'Missing bearer token.', 'missing_auth');
  }
  const token = header.slice(7).trim();
  if (!token) {
    throw new RankProgressionError(401, 'Missing bearer token.', 'missing_auth');
  }
  try {
    const verified = await jwtVerify(token, FIREBASE_JWKS, {
      algorithms: ['RS256'],
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
      audience: env.FIREBASE_PROJECT_ID,
    });
    if (!verified.payload.sub) throw new Error('Missing subject.');
    return verified.payload.sub;
  } catch {
    throw new RankProgressionError(401, 'Invalid or expired Firebase ID token.', 'invalid_auth');
  }
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('Invalid object.');
    }
    return value as Record<string, unknown>;
  } catch {
    throw new RankProgressionError(400, 'Invalid JSON body.', 'invalid_json');
  }
}

function json(
  env: RankProgressionEnv,
  status: number,
  body: unknown,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers':
        'authorization, content-type, x-firebase-appcheck',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
    },
  });
}
