export interface ProfileNameLockEnv {
  DB: D1Database;
}

const PROFILE_NAME_LOCK_TRIGGER = 'lock_confirmed_player_profile_name';

let installation: Promise<void> | null = null;

/**
 * A nickname is selected once for a player account. The first profile update is
 * allowed while profile_confirmed is false; later attempts to change the public
 * username or display name are rejected by D1 itself, independent of the app.
 */
export async function ensureProfileNameLockSchema(
  env: ProfileNameLockEnv,
): Promise<void> {
  installation ??= installProfileNameLockSchema(env).catch((error: unknown) => {
    installation = null;
    throw error;
  });
  await installation;
}

async function installProfileNameLockSchema(
  env: ProfileNameLockEnv,
): Promise<void> {
  await env.DB.prepare(
    `DROP TRIGGER IF EXISTS ${PROFILE_NAME_LOCK_TRIGGER}`,
  ).run();

  await env.DB.prepare(
    `CREATE TRIGGER ${PROFILE_NAME_LOCK_TRIGGER}
     BEFORE UPDATE OF username, username_normalized, display_name ON players
     WHEN OLD.profile_confirmed = 1
       AND (
         NEW.username != OLD.username
         OR NEW.username_normalized != OLD.username_normalized
         OR NEW.display_name != OLD.display_name
       )
     BEGIN
       SELECT RAISE(ABORT, 'profile_name_locked');
     END`,
  ).run();
}
