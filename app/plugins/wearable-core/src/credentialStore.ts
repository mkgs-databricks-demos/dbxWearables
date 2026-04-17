/**
 * CredentialStore — abstract over the wearable_credentials table.
 *
 * Default implementation talks to Lakebase via AppKit.lakebase. Customers
 * can subclass CredentialStore and plug in Vault / AWS Secrets Manager /
 * Azure Key Vault backends by replacing the exported default.
 */
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export interface Credentials {
  userId: string;
  provider: string;
  providerUserId: string;
  accessToken: string;
  refreshToken?: string;
  tokenExpiresAt?: Date;
  scopes: string[];
}

export interface EnrolledUser {
  userId: string;
  provider: string;
  providerUserId: string;
}

export interface CredentialStore {
  get(userId: string, provider: string): Promise<Credentials | null>;
  put(creds: Credentials): Promise<void>;
  revoke(userId: string, provider: string): Promise<void>;
  listEnrolled(provider?: string): Promise<EnrolledUser[]>;
}

interface LakebaseLike {
  query: (sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }>;
}

/**
 * Default CredentialStore backed by Lakebase.
 *
 * OAuth tokens are envelope-encrypted with AES-256-GCM using a per-row
 * data key wrapped by a signing key configured as a plugin resource.
 * The Python mirror in providers/common/credential_store.py must use
 * the same framing.
 *
 * Wire format (access_token_encrypted / refresh_token_encrypted columns):
 *   [1 byte version=0x01][12 bytes IV][16 bytes auth tag][N bytes ciphertext]
 */
export class LakebaseCredentialStore implements CredentialStore {
  constructor(
    private readonly lakebase: LakebaseLike,
    private readonly signingKey: Buffer,
  ) {
    if (signingKey.length !== 32) {
      throw new Error(
        "LakebaseCredentialStore signingKey must be exactly 32 bytes (256 bits).",
      );
    }
  }

  async get(userId: string, provider: string): Promise<Credentials | null> {
    const { rows } = await this.lakebase.query(
      `SELECT provider_user_id, access_token_encrypted, refresh_token_encrypted,
              token_expires_at, scopes
         FROM wearable_credentials
        WHERE user_id = $1 AND provider = $2 AND revoked_at IS NULL`,
      [userId, provider],
    );
    if (rows.length === 0) return null;
    const r = rows[0] as {
      provider_user_id: string;
      access_token_encrypted: Buffer;
      refresh_token_encrypted: Buffer | null;
      token_expires_at: Date | null;
      scopes: string[];
    };
    return {
      userId,
      provider,
      providerUserId: r.provider_user_id,
      accessToken: this.decrypt(r.access_token_encrypted),
      refreshToken: r.refresh_token_encrypted
        ? this.decrypt(r.refresh_token_encrypted)
        : undefined,
      tokenExpiresAt: r.token_expires_at ?? undefined,
      scopes: r.scopes ?? [],
    };
  }

  async put(creds: Credentials): Promise<void> {
    await this.lakebase.query(
      `INSERT INTO wearable_credentials (
          user_id, provider, provider_user_id,
          access_token_encrypted, refresh_token_encrypted,
          token_expires_at, scopes, revoked_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, NULL)
        ON CONFLICT (user_id, provider) DO UPDATE SET
          provider_user_id        = EXCLUDED.provider_user_id,
          access_token_encrypted  = EXCLUDED.access_token_encrypted,
          refresh_token_encrypted = EXCLUDED.refresh_token_encrypted,
          token_expires_at        = EXCLUDED.token_expires_at,
          scopes                  = EXCLUDED.scopes,
          revoked_at              = NULL`,
      [
        creds.userId,
        creds.provider,
        creds.providerUserId,
        this.encrypt(creds.accessToken),
        creds.refreshToken ? this.encrypt(creds.refreshToken) : null,
        creds.tokenExpiresAt ?? null,
        creds.scopes,
      ],
    );
  }

  async revoke(userId: string, provider: string): Promise<void> {
    await this.lakebase.query(
      `UPDATE wearable_credentials
          SET revoked_at = now()
        WHERE user_id = $1 AND provider = $2 AND revoked_at IS NULL`,
      [userId, provider],
    );
  }

  async listEnrolled(provider?: string): Promise<EnrolledUser[]> {
    const sql = provider
      ? `SELECT user_id, provider, provider_user_id
           FROM wearable_credentials
          WHERE revoked_at IS NULL AND provider = $1
          ORDER BY user_id`
      : `SELECT user_id, provider, provider_user_id
           FROM wearable_credentials
          WHERE revoked_at IS NULL
          ORDER BY provider, user_id`;
    const { rows } = await this.lakebase.query(
      sql,
      provider ? [provider] : [],
    );
    return (rows as Array<{
      user_id: string;
      provider: string;
      provider_user_id: string;
    }>).map((r) => ({
      userId: r.user_id,
      provider: r.provider,
      providerUserId: r.provider_user_id,
    }));
  }

  // ------------------------------------------------------------------
  // Envelope encryption (AES-256-GCM)
  // ------------------------------------------------------------------

  private encrypt(plaintext: string): Buffer {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.signingKey, iv);
    const encrypted = Buffer.concat([
      cipher.update(plaintext, "utf8"),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    return Buffer.concat([Buffer.from([0x01]), iv, tag, encrypted]);
  }

  private decrypt(envelope: Buffer): string {
    if (envelope.length < 1 + 12 + 16 + 1) {
      throw new Error("Ciphertext too short");
    }
    const version = envelope[0];
    if (version !== 0x01) {
      throw new Error(`Unsupported credential envelope version: ${version}`);
    }
    const iv = envelope.subarray(1, 13);
    const tag = envelope.subarray(13, 29);
    const ciphertext = envelope.subarray(29);
    const decipher = createDecipheriv("aes-256-gcm", this.signingKey, iv);
    decipher.setAuthTag(tag);
    const plaintext = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]);
    return plaintext.toString("utf8");
  }
}
