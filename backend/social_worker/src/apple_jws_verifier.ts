export class AppleJwsVerificationError extends Error {
  constructor(
    message: string,
    readonly code = 'invalid_apple_signature',
  ) {
    super(message);
  }
}

export type AppleJwsVerificationOptions = {
  trustedRootCertificatesPem: string;
  expectedBundleId: string;
  expectedEnvironment?: 'production' | 'sandbox';
  now?: Date;
};

type DerNode = {
  tag: number;
  start: number;
  contentStart: number;
  end: number;
};

type ParsedCertificate = {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithmOid: string;
  signature: Uint8Array;
  subjectPublicKeyInfo: Uint8Array;
  notBefore: Date;
  notAfter: Date;
};

const OID_SHA256_WITH_RSA = '1.2.840.113549.1.1.11';
const OID_SHA384_WITH_RSA = '1.2.840.113549.1.1.12';
const OID_ECDSA_WITH_SHA256 = '1.2.840.10045.4.3.2';
const OID_ECDSA_WITH_SHA384 = '1.2.840.10045.4.3.3';

export async function verifyAppleStoreKitJws(
  value: string,
  options: AppleJwsVerificationOptions,
): Promise<Record<string, unknown>> {
  const parts = value.split('.');
  if (parts.length !== 3 || parts.some((part) => !part)) {
    throw new AppleJwsVerificationError(
      'The App Store transaction is not a compact JWS.',
    );
  }

  const header = parseJson(base64UrlDecode(parts[0]), 'JWS header');
  if (header.alg !== 'ES256') {
    throw new AppleJwsVerificationError(
      'The App Store transaction does not use ES256.',
    );
  }
  const x5c = Array.isArray(header.x5c)
    ? header.x5c.filter((item): item is string => typeof item === 'string')
    : [];
  if (x5c.length < 2) {
    throw new AppleJwsVerificationError(
      'The App Store transaction certificate chain is missing.',
    );
  }

  const certificates = x5c.map((encoded) =>
    parseCertificate(base64Decode(encoded)),
  );
  const trustedRoots = parsePemCertificates(options.trustedRootCertificatesPem)
    .map(parseCertificate);
  if (trustedRoots.length === 0) {
    throw new AppleJwsVerificationError(
      'No trusted Apple root certificate is configured.',
      'apple_root_certificate_missing',
    );
  }

  const now = options.now ?? new Date();
  for (const certificate of certificates) {
    assertCertificateTime(certificate, now);
  }
  for (let index = 0; index < certificates.length - 1; index++) {
    await verifyCertificateSignature(
      certificates[index],
      certificates[index + 1],
    );
  }
  await assertAnchoredToTrustedRoot(
    certificates[certificates.length - 1],
    trustedRoots,
    now,
  );

  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const jwsSignature = base64UrlDecode(parts[2]);
  if (jwsSignature.length !== 64) {
    throw new AppleJwsVerificationError(
      'The App Store JWS signature has an invalid length.',
    );
  }
  const leafKey = await crypto.subtle.importKey(
    'spki',
    toArrayBuffer(certificates[0].subjectPublicKeyInfo),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );
  const signatureValid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    leafKey,
    toArrayBuffer(jwsSignature),
    toArrayBuffer(signingInput),
  );
  if (!signatureValid) {
    throw new AppleJwsVerificationError(
      'The App Store JWS signature is invalid.',
    );
  }

  const payload = parseJson(base64UrlDecode(parts[1]), 'JWS payload');
  const nestedData = objectValue(payload.data);
  const bundleId =
    stringValue(payload.bundleId) ?? stringValue(nestedData?.bundleId);
  if (bundleId !== options.expectedBundleId) {
    throw new AppleJwsVerificationError(
      'The App Store bundle identifier does not match this app.',
      'bundle_mismatch',
    );
  }

  const environment = (
    stringValue(payload.environment) ??
    stringValue(nestedData?.environment)
  )?.toLowerCase();
  if (
    options.expectedEnvironment &&
    environment &&
    environment !== options.expectedEnvironment
  ) {
    throw new AppleJwsVerificationError(
      'The App Store transaction environment does not match.',
      'environment_mismatch',
    );
  }
  return payload;
}

async function assertAnchoredToTrustedRoot(
  chainTail: ParsedCertificate,
  trustedRoots: ParsedCertificate[],
  now: Date,
): Promise<void> {
  for (const root of trustedRoots) {
    try {
      assertCertificateTime(root, now);
      if (equalBytes(chainTail.der, root.der)) return;
      await verifyCertificateSignature(chainTail, root);
      return;
    } catch {
      // An expired, incompatible, or non-matching root must not prevent
      // trying the remaining explicitly trusted Apple roots.
    }
  }
  throw new AppleJwsVerificationError(
    'The App Store certificate chain is not anchored to a trusted Apple root.',
  );
}

async function verifyCertificateSignature(
  certificate: ParsedCertificate,
  issuer: ParsedCertificate,
): Promise<void> {
  let key: CryptoKey;
  let algorithm: AlgorithmIdentifier | EcdsaParams;
  let signature = certificate.signature;

  if (
    certificate.signatureAlgorithmOid === OID_SHA256_WITH_RSA ||
    certificate.signatureAlgorithmOid === OID_SHA384_WITH_RSA
  ) {
    const hash =
      certificate.signatureAlgorithmOid === OID_SHA384_WITH_RSA
        ? 'SHA-384'
        : 'SHA-256';
    key = await crypto.subtle.importKey(
      'spki',
      toArrayBuffer(issuer.subjectPublicKeyInfo),
      { name: 'RSASSA-PKCS1-v1_5', hash },
      false,
      ['verify'],
    );
    algorithm = { name: 'RSASSA-PKCS1-v1_5' };
  } else if (
    certificate.signatureAlgorithmOid === OID_ECDSA_WITH_SHA256 ||
    certificate.signatureAlgorithmOid === OID_ECDSA_WITH_SHA384
  ) {
    const usesSha384 =
      certificate.signatureAlgorithmOid === OID_ECDSA_WITH_SHA384;
    const namedCurve = usesSha384 ? 'P-384' : 'P-256';
    const hash = usesSha384 ? 'SHA-384' : 'SHA-256';
    const signatureWidth = usesSha384 ? 48 : 32;

    key = await crypto.subtle.importKey(
      'spki',
      toArrayBuffer(issuer.subjectPublicKeyInfo),
      { name: 'ECDSA', namedCurve },
      false,
      ['verify'],
    );
    algorithm = { name: 'ECDSA', hash };
    signature = ecdsaDerToRaw(signature, signatureWidth);
  } else {
    throw new AppleJwsVerificationError(
      `Unsupported Apple certificate signature algorithm: ${certificate.signatureAlgorithmOid}`,
    );
  }

  const valid = await crypto.subtle.verify(
    algorithm,
    key,
    toArrayBuffer(signature),
    toArrayBuffer(certificate.tbs),
  );
  if (!valid) {
    throw new AppleJwsVerificationError(
      'The App Store certificate chain signature is invalid.',
    );
  }
}

function parseCertificate(der: Uint8Array): ParsedCertificate {
  const root = readNode(der, 0);
  if (root.tag !== 0x30 || root.end !== der.length) {
    throw new AppleJwsVerificationError('Invalid X.509 certificate encoding.');
  }
  const certificateChildren = readChildren(der, root);
  if (certificateChildren.length < 3) {
    throw new AppleJwsVerificationError('Incomplete X.509 certificate.');
  }

  const tbsNode = certificateChildren[0];
  const algorithmNode = certificateChildren[1];
  const signatureNode = certificateChildren[2];
  const algorithmChildren = readChildren(der, algorithmNode);
  if (algorithmChildren.length === 0 || algorithmChildren[0].tag !== 0x06) {
    throw new AppleJwsVerificationError(
      'The X.509 signature algorithm is missing.',
    );
  }
  const signatureAlgorithmOid = decodeOid(
    sliceContent(der, algorithmChildren[0]),
  );
  if (signatureNode.tag !== 0x03) {
    throw new AppleJwsVerificationError('The X.509 signature is missing.');
  }
  const bitString = sliceContent(der, signatureNode);
  if (bitString.length < 2 || bitString[0] !== 0) {
    throw new AppleJwsVerificationError('Invalid X.509 signature bit string.');
  }

  const tbsChildren = readChildren(der, tbsNode);
  const index = tbsChildren[0]?.tag === 0xa0 ? 1 : 0;
  if (tbsChildren.length < index + 6) {
    throw new AppleJwsVerificationError('Incomplete X.509 TBSCertificate.');
  }
  const validityNode = tbsChildren[index + 3];
  const spkiNode = tbsChildren[index + 5];
  const validity = readChildren(der, validityNode);
  if (validity.length !== 2) {
    throw new AppleJwsVerificationError('Invalid X.509 validity range.');
  }

  return {
    der,
    tbs: sliceNode(der, tbsNode),
    signatureAlgorithmOid,
    signature: bitString.slice(1),
    subjectPublicKeyInfo: sliceNode(der, spkiNode),
    notBefore: parseAsn1Time(der, validity[0]),
    notAfter: parseAsn1Time(der, validity[1]),
  };
}

function assertCertificateTime(
  certificate: ParsedCertificate,
  now: Date,
): void {
  const timestamp = now.getTime();
  if (
    !Number.isFinite(certificate.notBefore.getTime()) ||
    !Number.isFinite(certificate.notAfter.getTime()) ||
    timestamp < certificate.notBefore.getTime() ||
    timestamp > certificate.notAfter.getTime()
  ) {
    throw new AppleJwsVerificationError(
      'An App Store signing certificate is expired or not yet valid.',
    );
  }
}

function readNode(bytes: Uint8Array, offset: number): DerNode {
  if (offset < 0 || offset >= bytes.length) {
    throw new AppleJwsVerificationError('Invalid DER offset.');
  }
  const tag = bytes[offset];
  const lengthByte = bytes[offset + 1];
  if (lengthByte == null) {
    throw new AppleJwsVerificationError('Invalid DER length.');
  }

  let contentLength = 0;
  let lengthBytes = 1;
  if ((lengthByte & 0x80) === 0) {
    contentLength = lengthByte;
  } else {
    const count = lengthByte & 0x7f;
    if (count === 0 || count > 4 || offset + 2 + count > bytes.length) {
      throw new AppleJwsVerificationError('Unsupported DER length.');
    }
    lengthBytes += count;
    for (let index = 0; index < count; index++) {
      contentLength = (contentLength << 8) | bytes[offset + 2 + index];
    }
  }

  const contentStart = offset + 1 + lengthBytes;
  const end = contentStart + contentLength;
  if (end > bytes.length) {
    throw new AppleJwsVerificationError('DER node exceeds input length.');
  }
  return { tag, start: offset, contentStart, end };
}

function readChildren(bytes: Uint8Array, node: DerNode): DerNode[] {
  const children: DerNode[] = [];
  let offset = node.contentStart;
  while (offset < node.end) {
    const child = readNode(bytes, offset);
    children.push(child);
    offset = child.end;
  }
  if (offset !== node.end) {
    throw new AppleJwsVerificationError('Invalid DER child boundaries.');
  }
  return children;
}

function sliceNode(bytes: Uint8Array, node: DerNode): Uint8Array {
  return bytes.slice(node.start, node.end);
}

function sliceContent(bytes: Uint8Array, node: DerNode): Uint8Array {
  return bytes.slice(node.contentStart, node.end);
}

function decodeOid(bytes: Uint8Array): string {
  if (bytes.length === 0) {
    throw new AppleJwsVerificationError('Invalid ASN.1 OID.');
  }
  const result = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (let index = 1; index < bytes.length; index++) {
    value = (value << 7) | (bytes[index] & 0x7f);
    if ((bytes[index] & 0x80) === 0) {
      result.push(value);
      value = 0;
    }
  }
  if (value !== 0) throw new AppleJwsVerificationError('Invalid ASN.1 OID.');
  return result.join('.');
}

function parseAsn1Time(bytes: Uint8Array, node: DerNode): Date {
  if (node.tag !== 0x17 && node.tag !== 0x18) {
    throw new AppleJwsVerificationError('Unsupported X.509 time encoding.');
  }
  const value = new TextDecoder().decode(sliceContent(bytes, node));
  const match = node.tag === 0x17
    ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(value)
    : /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(value);
  if (!match) throw new AppleJwsVerificationError('Invalid X.509 time value.');

  const year = node.tag === 0x17
    ? Number(match[1]) >= 50
      ? 1900 + Number(match[1])
      : 2000 + Number(match[1])
    : Number(match[1]);
  return new Date(Date.UTC(
    year,
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4]),
    Number(match[5]),
    Number(match[6]),
  ));
}

function ecdsaDerToRaw(signature: Uint8Array, width: number): Uint8Array {
  const sequence = readNode(signature, 0);
  if (sequence.tag !== 0x30 || sequence.end !== signature.length) {
    throw new AppleJwsVerificationError('Invalid ECDSA certificate signature.');
  }
  const values = readChildren(signature, sequence);
  if (values.length !== 2 || values.some((node) => node.tag !== 0x02)) {
    throw new AppleJwsVerificationError('Invalid ECDSA signature integers.');
  }

  const raw = new Uint8Array(width * 2);
  raw.set(normalizeInteger(sliceContent(signature, values[0]), width), 0);
  raw.set(normalizeInteger(sliceContent(signature, values[1]), width), width);
  return raw;
}

function normalizeInteger(value: Uint8Array, width: number): Uint8Array {
  let normalized = value;
  while (normalized.length > 1 && normalized[0] === 0) {
    normalized = normalized.slice(1);
  }
  if (normalized.length > width) {
    throw new AppleJwsVerificationError('ECDSA integer is too large.');
  }
  const result = new Uint8Array(width);
  result.set(normalized, width - normalized.length);
  return result;
}

function parsePemCertificates(value: string): Uint8Array[] {
  const matches = value.match(
    /-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g,
  ) ?? [];
  return matches.map((pem) => {
    const encoded = pem
      .replace(/-----BEGIN CERTIFICATE-----/g, '')
      .replace(/-----END CERTIFICATE-----/g, '')
      .replace(/\s+/g, '');
    return base64Decode(encoded);
  });
}

function parseJson(
  bytes: Uint8Array,
  label: string,
): Record<string, unknown> {
  try {
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error();
    }
    return parsed as Record<string, unknown>;
  } catch {
    throw new AppleJwsVerificationError(`The App Store ${label} is invalid.`);
  }
}

function base64UrlDecode(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  return base64Decode(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '='));
}

function base64Decode(value: string): Uint8Array {
  try {
    const decoded = atob(value.replace(/\s+/g, ''));
    return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
  } catch {
    throw new AppleJwsVerificationError('Invalid Base64 certificate data.');
  }
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}