import type { RankProgressionEnv } from './rank_progression';

let schemaPromise: Promise<void> | null = null;

/**
 * Runtime safety net for the additive visible-RP/profile identity layer.
 *
 * D1 migrations remain the canonical production schema. This guard exists so a
 * newly deployed client/worker cannot break online play if the migration and
 * worker rollout are briefly out of order. It creates only new tables/indexes
 * and inserts additive achievement metadata; no existing duel, matchmaking,
 * Elo/MMR or escrow table is altered.
 */
export function ensureRankProgressionSchema(
  env: RankProgressionEnv,
): Promise<void> {
  return (schemaPromise ??= install(env).catch((error) => {
    schemaPromise = null;
    throw error;
  }));
}

async function install(env: RankProgressionEnv): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS player_rank_progression (
      player_id TEXT PRIMARY KEY,
      rank_points INTEGER NOT NULL DEFAULT 0 CHECK(rank_points >= 0),
      highest_rank_points INTEGER NOT NULL DEFAULT 0 CHECK(highest_rank_points >= 0),
      ranked_games INTEGER NOT NULL DEFAULT 0 CHECK(ranked_games >= 0),
      ranked_wins INTEGER NOT NULL DEFAULT 0 CHECK(ranked_wins >= 0),
      ranked_losses INTEGER NOT NULL DEFAULT 0 CHECK(ranked_losses >= 0),
      ranked_draws INTEGER NOT NULL DEFAULT 0 CHECK(ranked_draws >= 0),
      win_streak INTEGER NOT NULL DEFAULT 0 CHECK(win_streak >= 0),
      best_win_streak INTEGER NOT NULL DEFAULT 0 CHECK(best_win_streak >= 0),
      undefeated_streak INTEGER NOT NULL DEFAULT 0 CHECK(undefeated_streak >= 0),
      best_undefeated_streak INTEGER NOT NULL DEFAULT 0 CHECK(best_undefeated_streak >= 0),
      perfect_wins INTEGER NOT NULL DEFAULT 0 CHECK(perfect_wins >= 0),
      selected_avatar_key TEXT NOT NULL DEFAULT 'default',
      selected_frame_key TEXT NOT NULL DEFAULT 'auto',
      selected_title_key TEXT NOT NULL DEFAULT '',
      started_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
    )`),
    env.DB.prepare(`CREATE INDEX IF NOT EXISTS player_rank_progression_points_idx
      ON player_rank_progression(
        rank_points DESC, ranked_games DESC, updated_at ASC, player_id ASC
      )`),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS rank_progression_settlements (
      match_id TEXT NOT NULL,
      player_id TEXT NOT NULL,
      opponent_id TEXT NOT NULL,
      settlement_token TEXT NOT NULL,
      finished_at TEXT NOT NULL,
      result TEXT NOT NULL CHECK(result IN ('win', 'loss', 'draw')),
      finish_reason TEXT,
      player_mmr_before INTEGER NOT NULL,
      opponent_mmr_before INTEGER NOT NULL,
      base_delta INTEGER NOT NULL,
      alignment_percent INTEGER NOT NULL,
      repeat_percent INTEGER NOT NULL,
      abandonment_penalty INTEGER NOT NULL DEFAULT 0,
      rp_delta INTEGER NOT NULL,
      rp_before INTEGER NOT NULL,
      rp_after INTEGER NOT NULL,
      rank_before TEXT NOT NULL,
      rank_after TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(match_id, player_id),
      UNIQUE(settlement_token),
      FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
      FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
      FOREIGN KEY(opponent_id) REFERENCES players(id) ON DELETE CASCADE
    )`),
    env.DB.prepare(`CREATE INDEX IF NOT EXISTS rank_progression_pair_recent_idx
      ON rank_progression_settlements(player_id, opponent_id, finished_at DESC)`),
    env.DB.prepare(`CREATE INDEX IF NOT EXISTS rank_progression_player_time_idx
      ON rank_progression_settlements(player_id, finished_at ASC)`),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS rank_reward_grants (
      player_id TEXT NOT NULL,
      rank_key TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount > 0),
      granted_at TEXT NOT NULL,
      PRIMARY KEY(player_id, rank_key),
      FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
    )`),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS achievement_cosmetics (
      achievement_id TEXT PRIMARY KEY,
      decoration_key TEXT NOT NULL UNIQUE,
      rarity TEXT NOT NULL CHECK(rarity IN ('common', 'rare', 'epic', 'legendary')),
      sort_order INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(achievement_id) REFERENCES achievement_definitions(id) ON DELETE CASCADE
    )`),
  ]);

  await env.DB.prepare(`CREATE TRIGGER IF NOT EXISTS rank_reward_grant_apply
    AFTER INSERT ON rank_reward_grants
    BEGIN
      UPDATE players
         SET online_coins = online_coins + NEW.amount,
             updated_at = NEW.granted_at
       WHERE id = NEW.player_id;

      INSERT OR IGNORE INTO coin_ledger (
        id, player_id, amount, balance_after, reason,
        reference_type, reference_id, idempotency_key, metadata_json, created_at
      ) VALUES (
        lower(hex(randomblob(16))),
        NEW.player_id,
        NEW.amount,
        (SELECT online_coins FROM players WHERE id = NEW.player_id),
        'achievement_reward',
        'rank',
        NEW.rank_key,
        'rank_reward:' || NEW.player_id || ':' || NEW.rank_key,
        json_object(
          'source', 'rank_progression',
          'rankKey', NEW.rank_key,
          'lifetimeFirstTime', 1
        ),
        NEW.granted_at
      );
    END`).run();

  const definitions: ReadonlyArray<readonly [
    string,
    string,
    string,
    string,
    string,
    number,
  ]> = [
    ['undefeated_10', 'ranked', 'Unbeaten 10', 'Finish 10 ranked duels in a row without a loss.', 'silver', 120],
    ['undefeated_25', 'ranked', 'Unbeaten 25', 'Finish 25 ranked duels in a row without a loss.', 'gold', 130],
    ['undefeated_50', 'ranked', 'Unbeaten 50', 'Finish 50 ranked duels in a row without a loss.', 'milestone', 140],
    ['win_streak_5', 'ranked', 'Five Win Streak', 'Win 5 ranked duels in a row.', 'bronze', 150],
    ['win_streak_10', 'ranked', 'Ten Win Streak', 'Win 10 ranked duels in a row.', 'gold', 160],
    ['win_streak_25', 'ranked', 'Twenty Five Win Streak', 'Win 25 ranked duels in a row.', 'milestone', 170],
    ['rank_silver', 'season', 'Silver Competitor', 'Reach Silver III for the first time.', 'silver', 180],
    ['rank_gold', 'season', 'Gold Competitor', 'Reach Gold III for the first time.', 'gold', 190],
    ['rank_platinum', 'season', 'Platinum Competitor', 'Reach Platinum III for the first time.', 'platinum', 200],
    ['rank_master', 'season', 'Master Competitor', 'Reach Master III for the first time.', 'milestone', 210],
    ['rank_master_i', 'season', 'Master I', 'Reach Master I for the first time.', 'milestone', 220],
    ['giant_slayer', 'ranked', 'Giant Slayer', 'Defeat a ranked opponent at least 251 MMR above you.', 'gold', 230],
    ['ranked_veteran_100', 'ranked', 'Ranked Veteran', 'Finish 100 ranked duels.', 'silver', 240],
    ['ranked_veteran_500', 'ranked', 'Elite Veteran', 'Finish 500 ranked duels.', 'platinum', 250],
    ['ranked_veteran_1000', 'ranked', 'Legendary Veteran', 'Finish 1000 ranked duels.', 'milestone', 260],
    ['perfect_ranked_win', 'sudoku', 'Perfect Duel', 'Win a ranked duel without a mistake or timeout.', 'silver', 270],
    ['perfect_ranked_wins_10', 'sudoku', 'Perfect Ten', 'Win 10 ranked duels without a mistake or timeout.', 'platinum', 280],
  ];

  await env.DB.batch(
    definitions.map(([id, category, title, description, tier, sortOrder]) =>
      env.DB.prepare(`INSERT OR IGNORE INTO achievement_definitions (
        id, category, title, description, tier, reward_amount,
        platform_mirror_key, platform_mirror_enabled, sort_order
      ) VALUES (?, ?, ?, ?, ?, 0, NULL, 0, ?)`)
        .bind(id, category, title, description, tier, sortOrder),
    ),
  );

  const cosmetics: ReadonlyArray<readonly [string, string, string, number]> = [
    ['first_win', 'first_victory', 'common', 10],
    ['wins_10', 'ten_wins', 'rare', 20],
    ['games_25', 'duelist_25', 'rare', 30],
    ['wins_50', 'fifty_wins', 'epic', 40],
    ['wins_250', 'duel_legend', 'legendary', 50],
    ['daily_streak_7', 'focus_flame', 'rare', 60],
    ['country_contributor', 'country_crest', 'rare', 70],
    ['tournament_podium', 'podium_medal', 'epic', 80],
    ['friend_link', 'friendly_rival', 'common', 90],
    ['undefeated_10', 'unbeaten_shield_10', 'rare', 120],
    ['undefeated_25', 'unbeaten_shield_25', 'epic', 130],
    ['undefeated_50', 'unbeaten_shield_50', 'legendary', 140],
    ['win_streak_5', 'streak_flame_5', 'common', 150],
    ['win_streak_10', 'streak_flame_10', 'epic', 160],
    ['win_streak_25', 'streak_flame_25', 'legendary', 170],
    ['rank_silver', 'silver_crest', 'rare', 180],
    ['rank_gold', 'gold_crest', 'epic', 190],
    ['rank_platinum', 'platinum_crystal', 'epic', 200],
    ['rank_master', 'master_crown', 'legendary', 210],
    ['rank_master_i', 'master_i_crown', 'legendary', 220],
    ['giant_slayer', 'giant_slayer', 'epic', 230],
    ['ranked_veteran_100', 'veteran_100', 'rare', 240],
    ['ranked_veteran_500', 'veteran_500', 'epic', 250],
    ['ranked_veteran_1000', 'veteran_1000', 'legendary', 260],
    ['perfect_ranked_win', 'perfect_star', 'rare', 270],
    ['perfect_ranked_wins_10', 'perfect_crystal_star', 'legendary', 280],
  ];

  await env.DB.batch(
    cosmetics.map(([achievementId, decorationKey, rarity, sortOrder]) =>
      env.DB.prepare(`INSERT OR IGNORE INTO achievement_cosmetics (
        achievement_id, decoration_key, rarity, sort_order
      ) VALUES (?, ?, ?, ?)`)
        .bind(achievementId, decorationKey, rarity, sortOrder),
    ),
  );
}
