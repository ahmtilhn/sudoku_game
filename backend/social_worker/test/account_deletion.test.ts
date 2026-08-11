import { describe, expect, it } from 'vitest';

import {
  AccountDeletionError,
  deletePlayerAccountData,
  isAccountDeletionPath,
} from '../src/account_deletion';

describe('account deletion routing', () => {
  it('recognizes only the account deletion endpoint', () => {
    expect(isAccountDeletionPath('/v1/me/delete')).toBe(true);
    expect(isAccountDeletionPath('/v1/me')).toBe(false);
    expect(isAccountDeletionPath('/v1/me/wallet')).toBe(false);
  });

  it('rejects unsupported methods before reading account data', async () => {
    await expect(
      deletePlayerAccountData(
        new Request('https://example.test/v1/me/delete', { method: 'GET' }),
        {
          DB: {} as D1Database,
          FIREBASE_PROJECT_ID: 'project-id',
        },
      ),
    ).rejects.toMatchObject({
      status: 405,
      code: 'method_not_allowed',
    } satisfies Partial<AccountDeletionError>);
  });
});
