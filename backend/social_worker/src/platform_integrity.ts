export type PlatformKind = 'game_center' | 'google_play_games';
export type HighValueRequestType =
  | 'tournament_start'
  | 'tournament_submit'
  | 'purchase_verification'
  | 'rewarded_reward';

export type GameCenterIdentityProof = {
  platformPlayerId: string;
  displayName?: string;
  bundleId: string;
  publicKeyUrl: string;
  signatureBase64: string;
  saltBase64: string;
  timestampMs: number;
};

export type GooglePlayGamesAuthResult = {
  platformPlayerId: string;
  displayName?: string;
  avatarUrl?: string;
};

export type VerifiedPlatformIdentity = {
  platform: PlatformKind;
  platformPlayerId: string;
  displayName?: string;
  avatarUrl?: string;
  verifiedAt: string;
  verificationMethod: 'game_center_signature' | 'google_server_auth_code';
};

export type IntegrityEvaluation = {
  allowed: boolean;
  code: string;
  riskState: 'monitor' | 'allow' | 'limited' | 'manual_review' | 'block';
  offlineAllowed: boolean;
};

export class PlatformIntegrityError extends Error {
  constructor(
    readonly code: string,
    message = 'Platform identity or integrity verification failed.',
  ) {
    super(message);
  }
}

export async function requestHashForBody(body: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalJson(body));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return hex(new Uint8Array(digest));
}

export async function tokenHash(token: string): Promise<string> {
  return requestHashForBody({ token });
}

export async function verifyGameCenterIdentity(
  proof: GameCenterIdentityProof,
  config: {
    bundleId: string;
    maxAgeMs?: number;
    nowMs?: number;
  },
  verifier: (proof: GameCenterIdentityProof) => Promise<boolean>,
): Promise<VerifiedPlatformIdentity> {
  const nowMs = config.nowMs ?? Date.now();
  const maxAgeMs = config.maxAgeMs ?? 5 * 60 * 1000;
  if (!proof.platformPlayerId.trim()) {
    throw new PlatformIntegrityError('platform_player_id_missing');
  }
  if (proof.bundleId !== config.bundleId) {
    throw new PlatformIntegrityError('bundle_id_mismatch');
  }
  if (!isTrustedApplePublicKeyUrl(proof.publicKeyUrl)) {
    throw new PlatformIntegrityError('invalid_public_key_url');
  }
  if (Math.abs(nowMs - proof.timestampMs) > maxAgeMs) {
    throw new PlatformIntegrityError('expired_signature');
  }
  if (!proof.signatureBase64 || !proof.saltBase64) {
    throw new PlatformIntegrityError('signature_material_missing');
  }
  if (!(await verifier(proof))) {
    throw new PlatformIntegrityError('invalid_signature');
  }
  return {
    platform: 'game_center',
    platformPlayerId: proof.platformPlayerId,
    displayName: normalizedOptional(proof.displayName),
    verifiedAt: new Date(nowMs).toISOString(),
    verificationMethod: 'game_center_signature',
  };
}

export async function verifyGooglePlayGamesAuthCode(
  input: {
    serverAuthCode: string;
    clientPlatformPlayerId?: string;
    nowMs?: number;
  },
  exchange: (serverAuthCode: string) => Promise<GooglePlayGamesAuthResult>,
  replayStore: {
    consume: (codeHash: string) => Promise<boolean>;
  },
): Promise<VerifiedPlatformIdentity> {
  const code = input.serverAuthCode.trim();
  if (!code) throw new PlatformIntegrityError('server_auth_code_missing');
  const consumed = await replayStore.consume(await tokenHash(code));
  if (!consumed) throw new PlatformIntegrityError('server_auth_code_replay');
  const result = await exchange(code);
  if (!result.platformPlayerId.trim()) {
    throw new PlatformIntegrityError('platform_player_id_missing');
  }
  if (
    input.clientPlatformPlayerId &&
    input.clientPlatformPlayerId !== result.platformPlayerId
  ) {
    throw new PlatformIntegrityError('client_player_id_mismatch');
  }
  return {
    platform: 'google_play_games',
    platformPlayerId: result.platformPlayerId,
    displayName: normalizedOptional(result.displayName),
    avatarUrl: normalizedOptional(result.avatarUrl),
    verifiedAt: new Date(input.nowMs ?? Date.now()).toISOString(),
    verificationMethod: 'google_server_auth_code',
  };
}

export function evaluateHighValueIntegrity(input: {
  requestType: HighValueRequestType;
  expectedRequestHash: string;
  attestedRequestHash?: string | null;
  appCheckRequired: boolean;
  appCheckPresent: boolean;
  attestationSupported: boolean;
  attestationPassed?: boolean;
  enforcementEnabled: boolean;
}): IntegrityEvaluation {
  if (input.appCheckRequired && !input.appCheckPresent) {
    return fail('app_check_missing', input.enforcementEnabled);
  }
  if (!input.attestationSupported) {
    return {
      allowed: true,
      code: 'attestation_unsupported',
      riskState: 'manual_review',
      offlineAllowed: true,
    };
  }
  if (!input.attestedRequestHash) {
    return fail('attestation_missing', input.enforcementEnabled);
  }
  if (input.attestedRequestHash !== input.expectedRequestHash) {
    return fail('integrity_hash_mismatch', input.enforcementEnabled);
  }
  if (input.attestationPassed === false) {
    return fail('attestation_failed', input.enforcementEnabled);
  }
  return {
    allowed: true,
    code: input.enforcementEnabled ? 'integrity_passed' : 'integrity_monitor',
    riskState: input.enforcementEnabled ? 'allow' : 'monitor',
    offlineAllowed: true,
  };
}

export function accountSwitchDecision(
  existingPlatformPlayerId: string | null,
  verifiedPlatformPlayerId: string,
): 'link' | 'same_account' | 'requires_user_confirmation' {
  if (!existingPlatformPlayerId) return 'link';
  return existingPlatformPlayerId === verifiedPlatformPlayerId
    ? 'same_account'
    : 'requires_user_confirmation';
}

export function platformFriendsImportDecision(input: {
  consentGranted: boolean;
  platformAuthenticated: boolean;
  verifiedBackendIdentity: boolean;
}): { importAllowed: boolean; code: string } {
  if (!input.consentGranted) {
    return { importAllowed: false, code: 'friends_consent_denied' };
  }
  if (!input.platformAuthenticated || !input.verifiedBackendIdentity) {
    return { importAllowed: false, code: 'platform_identity_unverified' };
  }
  return { importAllowed: true, code: 'friends_import_allowed' };
}

function fail(code: string, enforcementEnabled: boolean): IntegrityEvaluation {
  return {
    allowed: !enforcementEnabled,
    code,
    riskState: enforcementEnabled ? 'block' : 'monitor',
    offlineAllowed: true,
  };
}

function isTrustedApplePublicKeyUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname.endsWith('.apple.com');
  } catch {
    return false;
  }
}

function normalizedOptional(value: string | undefined): string | undefined {
  const clean = value?.trim();
  return clean ? clean : undefined;
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`)
    .join(',')}}`;
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
