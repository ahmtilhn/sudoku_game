export interface TestEconomyEnv {
  DB: D1Database;
  ENVIRONMENT?: string;
  TEST_STARTER_COINS?: string;
}

const STARTER_GRANT_REASON = 'starter_grant';
const PRODUCTION_STARTER_COINS = 1000;
const DEFAULT_TEST_STARTER_COINS = 10000;
const LEGACY_UNLIMITED_BALANCE_THRESHOLD = 900000000;
const TEST_STARTER_TRIGGER = 'upgrade_nonproduction_starter_grant';

let installation: Promise<void> | null = null;

/**
 * Keeps production economy untouched while making non-production accounts
 * start with a finite test balance. This deliberately replaces the old
 * DEBUG_UNLIMITED_COINS behavior; balances are never replenished after spend.
 */
export async function ensureTestEconomySchema(
  env: TestEconomyEnv,
): Promise<void> {
  const isProduction =
    (env.ENVIRONMENT ?? '').trim().toLowerCase() === 'production';

  if (isProduction) {
    await env.DB.prepare(
      `DROP TRIGGER IF EXISTS ${TEST_STARTER_TRIGGER}`,
    ).run();
    return;
  }

  installation ??= installTestEconomySchema(env).catch((error: unknown) => {
    installation = null;
    throw error;
  });
  await installation;
}

async function installTestEconomySchema(env: TestEconomyEnv): Promise<void> {
  const testStarterCoins = parseTestStarterCoins(env.TEST_STARTER_COINS);
  const additionalCoins = testStarterCoins - PRODUCTION_STARTER_COINS;

  await env.DB.prepare(
    `DROP TRIGGER IF EXISTS ${TEST_STARTER_TRIGGER}`,
  ).run();

  await env.DB.prepare(
    `CREATE TRIGGER ${TEST_STARTER_TRIGGER}
     AFTER INSERT ON coin_ledger
     WHEN NEW.reason = '${STARTER_GRANT_REASON}'
       AND NEW.amount = ${PRODUCTION_STARTER_COINS}
     BEGIN
       UPDATE players
       SET online_coins = online_coins + ${additionalCoins}
       WHERE id = NEW.player_id;

       UPDATE coin_ledger
       SET amount = ${testStarterCoins},
           metadata_json = json_set(
             COALESCE(metadata_json, '{}'),
             '$.testStarterCoins',
             ${testStarterCoins}
           )
       WHERE id = NEW.id;
     END`,
  ).run();

  // Old staging builds replenished accounts to 999,999,999 Coins. Normalize
  // only those unmistakable legacy debug balances; ordinary test balances and
  // all production balances remain untouched.
  await env.DB.prepare(
    `UPDATE players
     SET online_coins = ?, updated_at = ?
     WHERE online_coins >= ?`,
  )
    .bind(
      testStarterCoins,
      new Date().toISOString(),
      LEGACY_UNLIMITED_BALANCE_THRESHOLD,
    )
    .run();
}

function parseTestStarterCoins(value: string | undefined): number {
  const parsed = Number.parseInt(value ?? '', 10);
  if (
    Number.isSafeInteger(parsed) &&
    parsed >= PRODUCTION_STARTER_COINS &&
    parsed <= 1000000
  ) {
    return parsed;
  }
  return DEFAULT_TEST_STARTER_COINS;
}
