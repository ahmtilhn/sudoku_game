import { describe, expect, it } from 'vitest';

import {
  PlatformIntegrityError,
  accountSwitchDecision,
  evaluateHighValueIntegrity,
  platformFriendsImportDecision,
  requestHashForBody,
  verifyGameCenterIdentity,
  verifyGooglePlayGamesAuthCode,
} from '../src/platform_integrity';
import { platformMirrorRetryState } from '../src/competitive';

const nowMs = Date.parse('2026-07-28T12:00:00.000Z');

describe('platform identity and integrity policy', () => {
  it('keeps no-platform accounts unlinked until backend verification succeeds', () => {
    expect(accountSwitchDecision(null, 'gc-player-1')).toBe('link');
    expect(
      platformFriendsImportDecision({
        consentGranted: true,
        platformAuthenticated: false,
        verifiedBackendIdentity: false,
      }),
    ).toEqual({
      importAllowed: false,
      code: 'platform_identity_unverified',
    });
  });

  it('requires confirmation on platform account switch', () => {
    expect(accountSwitchDecision('old-player', 'new-player')).toBe(
      'requires_user_confirmation',
    );
  });

  it('rejects invalid and expired Game Center signatures', async () => {
    const proof = {
      platformPlayerId: 'game-player-1',
      bundleId: 'com.devoviastudio.sudoku',
      publicKeyUrl: 'https://static.gc.apple.com/public-key.cer',
      signatureBase64: 'signature',
      saltBase64: 'salt',
      timestampMs: nowMs,
    };

    await expect(
      verifyGameCenterIdentity(proof, { bundleId: proof.bundleId, nowMs }, async () => false),
    ).rejects.toMatchObject({ code: 'invalid_signature' });

    await expect(
      verifyGameCenterIdentity(
        { ...proof, timestampMs: nowMs - 10 * 60 * 1000 },
        { bundleId: proof.bundleId, nowMs },
        async () => true,
      ),
    ).rejects.toMatchObject({ code: 'expired_signature' });
  });

  it('accepts Game Center identity only after signature verification', async () => {
    const verified = await verifyGameCenterIdentity(
      {
        platformPlayerId: 'game-player-1',
        displayName: 'Ahmet',
        bundleId: 'com.devoviastudio.sudoku',
        publicKeyUrl: 'https://static.gc.apple.com/public-key.cer',
        signatureBase64: 'signature',
        saltBase64: 'salt',
        timestampMs: nowMs,
      },
      { bundleId: 'com.devoviastudio.sudoku', nowMs },
      async () => true,
    );

    expect(verified).toMatchObject({
      platform: 'game_center',
      platformPlayerId: 'game-player-1',
      verificationMethod: 'game_center_signature',
    });
  });

  it('prevents Google Play Games server auth code replay', async () => {
    const seen = new Set<string>();
    const replayStore = {
      consume: async (hash: string) => {
        if (seen.has(hash)) return false;
        seen.add(hash);
        return true;
      },
    };
    const exchange = async () => ({
      platformPlayerId: 'gpg-player-1',
      displayName: 'Player',
      avatarUrl: 'https://example.test/avatar.png',
    });

    await expect(
      verifyGooglePlayGamesAuthCode(
        { serverAuthCode: 'one-time-code', clientPlatformPlayerId: 'gpg-player-1', nowMs },
        exchange,
        replayStore,
      ),
    ).resolves.toMatchObject({
      platform: 'google_play_games',
      platformPlayerId: 'gpg-player-1',
    });

    await expect(
      verifyGooglePlayGamesAuthCode(
        { serverAuthCode: 'one-time-code', clientPlatformPlayerId: 'gpg-player-1', nowMs },
        exchange,
        replayStore,
      ),
    ).rejects.toBeInstanceOf(PlatformIntegrityError);
  });

  it('rejects client-supplied Google player ID mismatches', async () => {
    await expect(
      verifyGooglePlayGamesAuthCode(
        { serverAuthCode: 'code', clientPlatformPlayerId: 'tampered' },
        async () => ({ platformPlayerId: 'server-player' }),
        { consume: async () => true },
      ),
    ).rejects.toMatchObject({ code: 'client_player_id_mismatch' });
  });

  it('keeps App Check and requestHash policy separate from offline Sudoku', async () => {
    const requestHash = await requestHashForBody({
      requestType: 'tournament_submit',
      attemptId: 'attempt-1',
      bodyVersion: 1,
    });

    expect(
      evaluateHighValueIntegrity({
        requestType: 'tournament_submit',
        expectedRequestHash: requestHash,
        attestedRequestHash: requestHash,
        appCheckRequired: true,
        appCheckPresent: true,
        attestationSupported: true,
        attestationPassed: true,
        enforcementEnabled: true,
      }),
    ).toMatchObject({ allowed: true, offlineAllowed: true });

    expect(
      evaluateHighValueIntegrity({
        requestType: 'tournament_submit',
        expectedRequestHash: requestHash,
        attestedRequestHash: null,
        appCheckRequired: true,
        appCheckPresent: false,
        attestationSupported: true,
        enforcementEnabled: true,
      }),
    ).toMatchObject({
      allowed: false,
      code: 'app_check_missing',
      offlineAllowed: true,
    });
  });

  it('detects integrity hash mismatch and unsupported App Attest fallback', () => {
    expect(
      evaluateHighValueIntegrity({
        requestType: 'rewarded_reward',
        expectedRequestHash: 'expected',
        attestedRequestHash: 'different',
        appCheckRequired: false,
        appCheckPresent: false,
        attestationSupported: true,
        enforcementEnabled: true,
      }),
    ).toMatchObject({ allowed: false, code: 'integrity_hash_mismatch' });

    expect(
      evaluateHighValueIntegrity({
        requestType: 'tournament_start',
        expectedRequestHash: 'expected',
        attestedRequestHash: null,
        appCheckRequired: false,
        appCheckPresent: false,
        attestationSupported: false,
        enforcementEnabled: true,
      }),
    ).toMatchObject({
      allowed: true,
      code: 'attestation_unsupported',
      riskState: 'manual_review',
    });
  });

  it('does not roll back backend state on platform mirror retry failure', () => {
    expect(platformMirrorRetryState(false, 0)).toEqual({
      queueStatus: 'failed',
      unlockPreserved: true,
      attempts: 1,
    });
  });

  it('requires explicit friends consent before import', () => {
    expect(
      platformFriendsImportDecision({
        consentGranted: false,
        platformAuthenticated: true,
        verifiedBackendIdentity: true,
      }),
    ).toEqual({
      importAllowed: false,
      code: 'friends_consent_denied',
    });
  });
});
