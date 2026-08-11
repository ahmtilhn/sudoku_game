import type { DuelVariant } from './sudoku_variant';

export type VariantSchemaEnv = {
  DB: D1Database;
};

let schemaPromise: Promise<void> | null = null;

export function ensureVariantSchema(env: VariantSchemaEnv): Promise<void> {
  schemaPromise ??= installVariantSchema(env).catch((error) => {
    schemaPromise = null;
    throw error;
  });
  return schemaPromise;
}

async function installVariantSchema(env: VariantSchemaEnv): Promise<void> {
  await ensureColumn(
    env,
    'matches',
    'variant',
    "TEXT NOT NULL DEFAULT 'classic9' CHECK(variant IN ('classic9', 'classic16'))",
  );
  await ensureColumn(
    env,
    'matches',
    'board_size',
    'INTEGER NOT NULL DEFAULT 9 CHECK(board_size IN (9, 16))',
  );
  await ensureColumn(
    env,
    'matches',
    'cell_count',
    'INTEGER NOT NULL DEFAULT 81 CHECK(cell_count IN (81, 256))',
  );
  await ensureColumn(
    env,
    'challenges',
    'variant',
    "TEXT NOT NULL DEFAULT 'classic9' CHECK(variant IN ('classic9', 'classic16'))",
  );
  await ensureColumn(
    env,
    'ranked_queue',
    'variant',
    "TEXT NOT NULL DEFAULT 'classic9' CHECK(variant IN ('classic9', 'classic16'))",
  );
  await ensureColumn(
    env,
    'rematch_invitations',
    'variant',
    "TEXT NOT NULL DEFAULT 'classic9' CHECK(variant IN ('classic9', 'classic16'))",
  );
  await ensureColumn(
    env,
    'rematch_invitations',
    'mode',
    "TEXT NOT NULL DEFAULT 'friendly' CHECK(mode IN ('friendly', 'ranked'))",
  );

  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS player_variant_ratings (
       player_id TEXT NOT NULL,
       variant TEXT NOT NULL CHECK(variant IN ('classic9', 'classic16')),
       scope TEXT NOT NULL CHECK(scope IN ('global', 'beginner', 'easy', 'medium', 'hard', 'expert')),
       rating INTEGER NOT NULL DEFAULT 1000,
       games_played INTEGER NOT NULL DEFAULT 0,
       wins INTEGER NOT NULL DEFAULT 0,
       losses INTEGER NOT NULL DEFAULT 0,
       draws INTEGER NOT NULL DEFAULT 0,
       win_streak INTEGER NOT NULL DEFAULT 0,
       best_rating INTEGER NOT NULL DEFAULT 1000,
       provisional_games INTEGER NOT NULL DEFAULT 20,
       updated_at TEXT NOT NULL,
       PRIMARY KEY(player_id, variant, scope),
       FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
     )`,
  ).run();

  await env.DB.prepare(
    `CREATE INDEX IF NOT EXISTS ranked_queue_variant_difficulty_rating_idx
     ON ranked_queue(variant, difficulty, rating, joined_at)`,
  ).run();
  await env.DB.prepare(
    `CREATE INDEX IF NOT EXISTS matches_variant_difficulty_status_idx
     ON matches(variant, difficulty, status, updated_at DESC)`,
  ).run();
  await env.DB.prepare(
    `CREATE INDEX IF NOT EXISTS challenges_recipient_variant_status_idx
     ON challenges(recipient_id, variant, status, created_at DESC)`,
  ).run();
  await env.DB.prepare(
    `CREATE INDEX IF NOT EXISTS player_variant_ratings_leaderboard_idx
     ON player_variant_ratings(variant, scope, rating DESC, games_played DESC, updated_at ASC)`,
  ).run();

  const now = new Date().toISOString();
  for (const variant of ['classic9', 'classic16'] as const satisfies readonly DuelVariant[]) {
    if (variant === 'classic16') continue;
    await env.DB.prepare(
      `INSERT OR IGNORE INTO player_variant_ratings (
         player_id, variant, scope, rating, games_played, wins, losses,
         draws, win_streak, best_rating, provisional_games, updated_at
       )
       SELECT player_id, ?, scope, rating, games_played, wins, losses,
              draws, win_streak, best_rating, provisional_games, COALESCE(updated_at, ?)
       FROM player_ratings`,
    )
      .bind(variant, now)
      .run();
  }
}

async function ensureColumn(
  env: VariantSchemaEnv,
  table: string,
  column: string,
  declaration: string,
): Promise<void> {
  const rows = await env.DB.prepare(`PRAGMA table_info(${table})`).all<{
    name: string;
  }>();
  if (rows.results.some((row) => row.name === column)) return;
  await env.DB.prepare(
    `ALTER TABLE ${table} ADD COLUMN ${column} ${declaration}`,
  ).run();
}
