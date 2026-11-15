import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;
const AUTH_TAG_LENGTH = 16;
const KEY_LENGTH = 32;
const FORMAT_PREFIX = 'enc:v1:';

let cachedKey: Buffer | null = null;

/**
 * Parse the ENCRYPTION_KEY environment variable. Accepts either 64 hex
 * characters or base64 (standard or URL-safe) that decodes to 32 bytes.
 */
function parseKey(raw: string): Buffer {
  const value = raw.trim();

  let key: Buffer;
  if (/^[0-9a-fA-F]{64}$/.test(value)) {
    key = Buffer.from(value, 'hex');
  } else {
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
    key = Buffer.from(normalized, 'base64');
  }

  if (key.length !== KEY_LENGTH) {
    throw new Error(
      `ENCRYPTION_KEY must decode to exactly ${KEY_LENGTH} bytes ` +
        '(64 hex characters, or base64 of 32 bytes)'
    );
  }

  return key;
}

/**
 * Return the validated encryption key. Throws if the key is missing or invalid,
 * so the service fails fast rather than silently storing plaintext.
 */
export function getEncryptionKey(): Buffer {
  if (cachedKey) {
    return cachedKey;
  }

  const raw = process.env.ENCRYPTION_KEY;
  if (!raw || raw.trim() === '') {
    throw new Error(
      'ENCRYPTION_KEY is required. Generate one with: openssl rand -hex 32'
    );
  }

  cachedKey = parseKey(raw);
  return cachedKey;
}

/**
 * Verify encryption is configured. Call this during startup to fail fast.
 */
export function assertEncryptionConfigured(): void {
  getEncryptionKey();
}

/**
 * Encrypt a UTF-8 string with AES-256-GCM.
 * Output format: enc:v1:<iv base64>:<auth tag base64>:<ciphertext base64>
 */
export function encryptString(plaintext: string): string {
  const key = getEncryptionKey();
  const iv = randomBytes(IV_LENGTH);

  const cipher = createCipheriv(ALGORITHM, key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final()
  ]);
  const authTag = cipher.getAuthTag();

  return (
    FORMAT_PREFIX +
    [iv.toString('base64'), authTag.toString('base64'), ciphertext.toString('base64')].join(':')
  );
}

/**
 * Decrypt a value produced by encryptString().
 */
export function decryptString(value: string): string {
  if (!value.startsWith(FORMAT_PREFIX)) {
    throw new Error('Encrypted value has an unrecognized format');
  }

  const parts = value.slice(FORMAT_PREFIX.length).split(':');
  if (parts.length !== 3) {
    throw new Error('Encrypted value has an unrecognized format');
  }

  const [ivBase64, authTagBase64, ciphertextBase64] = parts;
  const iv = Buffer.from(ivBase64, 'base64');
  const authTag = Buffer.from(authTagBase64, 'base64');
  const ciphertext = Buffer.from(ciphertextBase64, 'base64');

  if (iv.length !== IV_LENGTH || authTag.length !== AUTH_TAG_LENGTH) {
    throw new Error('Encrypted value has invalid IV or authentication tag');
  }

  const key = getEncryptionKey();
  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(authTag);

  return Buffer.concat([
    decipher.update(ciphertext),
    decipher.final()
  ]).toString('utf8');
}

export function encryptOptional(value: string | undefined): string | undefined {
  return value === undefined ? undefined : encryptString(value);
}

export function decryptOptional(value: string | undefined): string | undefined {
  return value === undefined ? undefined : decryptString(value);
}
