import { describe, expect, it } from 'vitest';

import {
  StoreNotificationError,
  handleAppleServerNotification,
  handleGooglePlayRtdn,
  isAppleServerNotificationPath,
  isGooglePlayRtdnPath,
} from '../src/store_notifications';

const emptyDb = {} as D1Database;

describe('store notification routes', () => {
  it('recognizes only the explicit Google and Apple callback paths', () => {
    expect(isGooglePlayRtdnPath('/v1/store/google/rtdn')).toBe(true);
    expect(isGooglePlayRtdnPath('/v1/store/google')).toBe(false);
    expect(
      isAppleServerNotificationPath('/v1/store/apple/notifications'),
    ).toBe(true);
    expect(isAppleServerNotificationPath('/v1/store/apple')).toBe(false);
  });

  it('rejects notification handling outside production', async () => {
    await expect(
      handleGooglePlayRtdn(
        new Request('https://example.test/v1/store/google/rtdn', {
          method: 'POST',
        }),
        {
          DB: emptyDb,
          FIREBASE_PROJECT_ID: 'project-id',
          ENVIRONMENT: 'staging',
        },
      ),
    ).rejects.toMatchObject<Partial<StoreNotificationError>>({
      status: 400,
      code: 'invalid_environment',
    });
  });

  it('rejects unsupported methods before reading callback data', async () => {
    await expect(
      handleGooglePlayRtdn(
        new Request('https://example.test/v1/store/google/rtdn'),
        {
          DB: emptyDb,
          FIREBASE_PROJECT_ID: 'project-id',
          ENVIRONMENT: 'production',
        },
      ),
    ).rejects.toMatchObject<Partial<StoreNotificationError>>({
      status: 405,
      code: 'method_not_allowed',
    });

    await expect(
      handleAppleServerNotification(
        new Request('https://example.test/v1/store/apple/notifications'),
        {
          DB: emptyDb,
          FIREBASE_PROJECT_ID: 'project-id',
          ENVIRONMENT: 'production',
        },
      ),
    ).rejects.toMatchObject<Partial<StoreNotificationError>>({
      status: 405,
      code: 'method_not_allowed',
    });
  });

  it('rejects an unsigned App Store notification before database access', async () => {
    await expect(
      handleAppleServerNotification(
        new Request('https://example.test/v1/store/apple/notifications', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ signedPayload: 'unsigned.payload.value' }),
        }),
        {
          DB: emptyDb,
          FIREBASE_PROJECT_ID: 'project-id',
          ENVIRONMENT: 'production',
          APPLE_BUNDLE_ID: 'com.devoviastudio.sudoku',
          APPLE_ROOT_CERTIFICATES_PEM: [
            '-----BEGIN CERTIFICATE-----',
            'invalid',
            '-----END CERTIFICATE-----',
          ].join('\n'),
        },
      ),
    ).rejects.toMatchObject<Partial<StoreNotificationError>>({
      status: 401,
      code: 'invalid_apple_notification_signature',
    });
  });
});
