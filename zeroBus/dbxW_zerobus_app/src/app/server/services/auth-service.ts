// Auth Service — Singleton
//
// Manages app-level JWT authentication for mobile clients using Sign in
// with Apple. See client/src/pages/security/SecurityPage.tsx for the full
// architecture documentation and visual flow diagrams.
//
// Two-layer model:
//   Layer 1 (User -> App):  Sign in with Apple -> app-issued JWT (this service)
//   Layer 2 (App -> Workspace): M2M OAuth SPN (platform-managed, not here)
//
// Architecture:
//   - Apple JWKS validation: verify Apple identity tokens using Apple's public keys
//   - App JWT signing: issue short-lived access tokens (HS256, 15 min)
//   - Refresh tokens: opaque tokens with SHA-256 hashed storage in Lakebase
//   - User registry: Lakebase Postgres tables (auth.users, auth.devices, auth.refresh_tokens)
//
// Dependencies:
//   - jose: ESM-native JWT library (chosen over jsonwebtoken + jwks-rsa
//     for ESM compatibility — project uses "type": "module")
//   - AppKit Lakebase plugin: Postgres wire protocol via pg.Pool
//
// Environment variables (injected via app.yaml valueFrom directives):
//   JWT_SIGNING_SECRET  — HS256 signing key (from secret scope)
//   APPLE_BUNDLE_ID     — iOS app bundle identifier (for audience validation)
//
// Logging: Security-relevant events (token reuse, migration, init) are
// emitted as structured JSON via auth-logger.ts. Identifiers are SHA-256
// hashed before logging. Setup warnings retain human-readable console
// output for developer ergonomics (provisioning instructions).
//
// Timeouts: All external calls (Apple JWKS, Lakebase queries) are
// wrapped with explicit deadlines via withTimeout(). Throws TimeoutError
// on expiry, which route handlers map to HTTP 504.
//
// Apple JWKS endpoint (public, well-known):
//   The service fetches Apple's public signing keys at runtime to validate
//   identity tokens. The jose library caches keys automatically.

import crypto from 'node:crypto';
import { SignJWT, jwtVerify, createRemoteJWKSet, errors as joseErrors } from 'jose';
import { logAuthEvent } from '../utils/auth-logger.js';
import { withTimeout, TimeoutError } from '../utils/timeout.js';

// Re-export for route handlers (catch TimeoutError → 504)
export { TimeoutError } from '../utils/timeout.js';

// ── Configuration ─────────────────────────────────────────────────────

/** Access token lifetime. Short-lived — clients use refresh tokens to renew. */
const ACCESS_TOKEN_EXPIRY = '15m';

/** Refresh token lifetime in days. Stored as SHA-256 hash in Lakebase. */
const REFRESH_TOKEN_EXPIRY_DAYS = 30;

/** Access token expiry in seconds (for the expires_in response field). */
const ACCESS_TOKEN_EXPIRY_SECONDS = 900;

/** Apple identity token issuer claim. */
const APPLE_ISSUER = 'https://appleid.apple.com';

/** Apple JWKS endpoint path (appended to APPLE_ISSUER). */
const APPLE_JWKS_PATH = '/auth/keys';

// ── Timeout Configuration ─────────────────────────────────────────────
//
// Timeouts are tuned for mobile client latency expectations:
//   - Apple JWKS fetch is typically <500ms (cached), but the first fetch
//     or cache-miss can take 1-3s depending on Apple CDN latency.
//   - Lakebase queries are typically <100ms for single-row lookups, but
//     can spike during Lakebase scaling events.
//   - The overall Apple validation timeout covers the JWKS fetch + JWT
//     verification + nonce check as a single deadline.

/** HTTP timeout for fetching Apple's JWKS keys (passed to jose). */
const APPLE_JWKS_FETCH_TIMEOUT_MS = 5_000;

/** Overall timeout for Apple identity token validation (JWKS + verify + nonce). */
const APPLE_VALIDATION_TIMEOUT_MS = 10_000;

/** Timeout for individual Lakebase DML/query operations. */
const LAKEBASE_QUERY_TIMEOUT_MS = 5_000;

/** Timeout for Lakebase DDL operations (CREATE TABLE, migrations). */
const LAKEBASE_DDL_TIMEOUT_MS = 10_000;

// ── Types ─────────────────────────────────────────────────────────────

export interface AuthTokens {
  access_token: string;
  refresh_token: string;
  expires_in: number;       // seconds until access_token expires
  token_type: 'Bearer';
  user_id: string;          // Lakebase users.user_id UUID
}

export interface AppleTokenPayload {
  /** Apple's privacy-preserving, stable user identifier. */
  sub: string;
  /** User's email — only available on first authentication. */
  email?: string;
  email_verified?: boolean;
  /**
   * Apple's user fraud indicator (from the identity token).
   *   0 = unsupported (older OS)
   *   1 = unknown
   *   2 = likely real
   * Only present on the *first* authorization — subsequent sign-ins omit it.
   */
  real_user_status?: number;
}

export interface AccessTokenPayload {
  /** Lakebase users.user_id UUID. Written to bronze table user_id column. */
  sub: string;
  /** iOS Keychain device UUID (DeviceIdentifier.current). */
  device_id: string;
  /** Data source platform (e.g. "apple_healthkit"). */
  platform: string;
}

/** Lakebase client interface (matches AppKit lakebase plugin). */
interface LakebaseClient {
  query(text: string, params?: unknown[]): Promise<{ rows: Record<string, unknown>[] }>;
}

// ── Lakebase Migration SQL ────────────────────────────────────────────
//
// Tables live in the `auth` schema to isolate auth data from the
// existing `app` schema used by todo-routes.ts (sample scaffold).
//
// The migration is idempotent — safe to run on every app startup.

const MIGRATION_SQL = {
  createSchema: `CREATE SCHEMA IF NOT EXISTS auth`,

  checkTables: `
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'auth'
      AND table_name IN ('users', 'devices', 'refresh_tokens')
  `,

  createUsers: `
    CREATE TABLE IF NOT EXISTS auth.users (
      user_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      apple_sub     TEXT UNIQUE NOT NULL,
      display_name  TEXT,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `,

  createDevices: `
    CREATE TABLE IF NOT EXISTS auth.devices (
      device_id      TEXT PRIMARY KEY,
      user_id        UUID NOT NULL REFERENCES auth.users(user_id),
      platform       TEXT NOT NULL,
      app_version    TEXT,
      first_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `,

  createRefreshTokens: `
    CREATE TABLE IF NOT EXISTS auth.refresh_tokens (
      token_hash  TEXT PRIMARY KEY,
      user_id     UUID NOT NULL REFERENCES auth.users(user_id),
      device_id   TEXT NOT NULL REFERENCES auth.devices(device_id),
      expires_at  TIMESTAMPTZ NOT NULL,
      revoked_at  TIMESTAMPTZ,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `,
};

// ── Service class ─────────────────────────────────────────────────────

class AuthService {
  private lakebase: LakebaseClient | null = null;
  private jwtSecret: Uint8Array | null = null;
  private appleJwks: ReturnType<typeof createRemoteJWKSet> | null = null;
  private appleBundleId = '';
  private initialized = false;

  // ── Initialization ──────────────────────────────────────────────────

  /**
   * Initialize the auth service with the Lakebase client.
   * Must be called once at app startup (in server.ts) before handling
   * requests. Runs Lakebase migrations on first call.
   *
   * Graceful degradation: if JWT_SIGNING_SECRET is not set, the service
   * stays uninitialized and auth endpoints return 503. This allows the
   * app to run without auth during development or before secrets are
   * provisioned.
   */
  async setup(lakebase: LakebaseClient): Promise<void> {
    if (this.initialized) return;

    const signingSecret = process.env.JWT_SIGNING_SECRET;
    if (!signingSecret) {
      // Human-readable console warning with provisioning command
      console.warn(
        '[Auth] JWT_SIGNING_SECRET not set — auth endpoints will be unavailable. ' +
        'Provision the secret: databricks secrets put-secret ' +
        'dbxw_zerobus_credentials jwt_signing_secret --string-value "<secret>"',
      );
      logAuthEvent({
        event: 'service_init',
        outcome: 'warn',
        errorCode: 'MISSING_SECRET',
        errorDetail: 'JWT_SIGNING_SECRET not set',
      });
      return;
    }

    this.appleBundleId = process.env.APPLE_BUNDLE_ID || '';
    if (!this.appleBundleId) {
      // Human-readable console warning with provisioning command
      console.warn(
        '[Auth] APPLE_BUNDLE_ID not set — Apple token validation will reject all tokens. ' +
        'Provision the value: databricks secrets put-secret ' +
        'dbxw_zerobus_credentials apple_bundle_id --string-value "<bundle-id>"',
      );
      logAuthEvent({
        event: 'service_init',
        outcome: 'warn',
        errorCode: 'MISSING_CONFIG',
        errorDetail: 'APPLE_BUNDLE_ID not set',
      });
    }

    this.jwtSecret = new TextEncoder().encode(signingSecret);
    this.lakebase = lakebase;

    // Build the Apple JWKS URL from well-known components.
    // jose caches the fetched keys internally and refreshes as needed.
    // timeoutDuration controls the HTTP fetch timeout for key retrieval.
    const appleJwksUrl = new URL(APPLE_JWKS_PATH, APPLE_ISSUER);
    this.appleJwks = createRemoteJWKSet(appleJwksUrl, {
      timeoutDuration: APPLE_JWKS_FETCH_TIMEOUT_MS,
    });

    await this.migrate();

    this.initialized = true;
    logAuthEvent({
      event: 'service_init',
      outcome: 'success',
    });
  }

  /** Check if the service is properly initialized and ready to handle requests. */
  isReady(): boolean {
    return this.initialized;
  }

  // ── Lakebase Query Helper ───────────────────────────────────────────

  /**
   * Execute a Lakebase query with a timeout deadline.
   *
   * Consolidates the null check and timeout wrapping for all Lakebase
   * calls. The underlying query is NOT cancelled on timeout — it
   * continues in Postgres, but we stop waiting and throw TimeoutError.
   *
   * @param sql    - SQL query string (with $1, $2, ... placeholders)
   * @param params - Parameterized values
   * @param label  - Descriptive label for timeout error messages
   * @param timeoutMs - Override timeout (defaults to LAKEBASE_QUERY_TIMEOUT_MS)
   */
  private async query(
    sql: string,
    params?: unknown[],
    label = 'Lakebase query',
    timeoutMs = LAKEBASE_QUERY_TIMEOUT_MS,
  ): Promise<{ rows: Record<string, unknown>[] }> {
    if (!this.lakebase) {
      throw new Error('Auth service not initialized');
    }
    return withTimeout(this.lakebase.query(sql, params), timeoutMs, label);
  }

  // ── Lakebase Migration ──────────────────────────────────────────────

  /**
   * Create the auth schema and tables if they don't exist.
   * Idempotent — safe to run on every app startup.
   *
   * Uses LAKEBASE_DDL_TIMEOUT_MS (10s) for DDL operations, which may
   * be slower than DML on first run or during Lakebase scaling.
   */
  private async migrate(): Promise<void> {
    if (!this.lakebase) return;

    const start = Date.now();
    const tablesCreated: string[] = [];

    try {
      await this.query(MIGRATION_SQL.createSchema, undefined, 'CREATE SCHEMA', LAKEBASE_DDL_TIMEOUT_MS);

      const { rows } = await this.query(MIGRATION_SQL.checkTables, undefined, 'check auth tables', LAKEBASE_DDL_TIMEOUT_MS);
      const existing = new Set(rows.map((r) => r.table_name as string));

      if (!existing.has('users')) {
        await this.query(MIGRATION_SQL.createUsers, undefined, 'CREATE auth.users', LAKEBASE_DDL_TIMEOUT_MS);
        tablesCreated.push('auth.users');
      }
      if (!existing.has('devices')) {
        await this.query(MIGRATION_SQL.createDevices, undefined, 'CREATE auth.devices', LAKEBASE_DDL_TIMEOUT_MS);
        tablesCreated.push('auth.devices');
      }
      if (!existing.has('refresh_tokens')) {
        await this.query(MIGRATION_SQL.createRefreshTokens, undefined, 'CREATE auth.refresh_tokens', LAKEBASE_DDL_TIMEOUT_MS);
        tablesCreated.push('auth.refresh_tokens');
      }

      logAuthEvent({
        event: 'migration',
        outcome: 'success',
        durationMs: Date.now() - start,
        extra: {
          tables_created: tablesCreated,
          tables_existed: Array.from(existing),
        },
      });
    } catch (err) {
      logAuthEvent({
        event: 'migration',
        outcome: 'failure',
        errorDetail: (err as Error).message,
        durationMs: Date.now() - start,
        extra: {
          tables_created_before_error: tablesCreated,
        },
      });
      throw err;
    }
  }

  // ── Apple Token Validation ──────────────────────────────────────────

  /**
   * Validate an Apple identity token (JWT from ASAuthorizationAppleIDCredential).
   *
   * Fetches Apple's public keys from their JWKS endpoint (cached by jose),
   * verifies the RS256 signature, checks issuer + audience + expiry, verifies
   * the nonce (if provided) to prevent replay attacks, and extracts the `sub`
   * claim — Apple's stable, privacy-preserving user ID.
   *
   * The `sub` claim is consistent across all of a user's devices for the
   * same Apple Developer Team ID, making it a reliable primary key.
   *
   * Timeout: The entire validation (JWKS fetch + verify + nonce check) is
   * wrapped in APPLE_VALIDATION_TIMEOUT_MS (10s). The JWKS HTTP fetch itself
   * has a tighter APPLE_JWKS_FETCH_TIMEOUT_MS (5s) set on createRemoteJWKSet.
   *
   * @param identityToken - The raw JWT string from Apple (base64url-encoded)
   * @param nonce - Optional raw nonce from the iOS client. If provided, it is
   *   SHA-256 hashed and compared to the `nonce` claim in the Apple token.
   *   Apple embeds the hash set on the ASAuthorizationAppleIDRequest; this
   *   verification prevents replay of a captured identity token.
   * @throws Error if validation fails (expired, bad signature, wrong audience, nonce mismatch)
   * @throws TimeoutError if Apple's JWKS endpoint is unreachable within the deadline
   */
  async validateAppleToken(identityToken: string, nonce?: string): Promise<AppleTokenPayload> {
    if (!this.appleJwks) {
      throw new Error('Auth service not initialized');
    }

    try {
      // Wrap the entire JWKS fetch + JWT verification in a single deadline.
      // The jose JWKS function may trigger an HTTP fetch (cache miss) or use
      // cached keys (cache hit). Either way, we enforce an overall limit.
      const { payload } = await withTimeout(
        jwtVerify(identityToken, this.appleJwks, {
          issuer: APPLE_ISSUER,
          audience: this.appleBundleId,
        }),
        APPLE_VALIDATION_TIMEOUT_MS,
        'Apple token validation',
      );

      if (!payload.sub) {
        throw new Error('Apple identity token missing sub claim');
      }

      // ── Nonce verification (Apple CRITICAL best practice) ───────────
      //
      // The iOS app generates a raw nonce, SHA-256 hashes it, and sets
      // the hash on the ASAuthorizationAppleIDRequest. Apple embeds that
      // hash as the `nonce` claim in the identity token. We re-hash the
      // raw nonce from the request body and compare to prevent replay.
      if (nonce) {
        const expectedHash = crypto
          .createHash('sha256')
          .update(nonce)
          .digest('hex');
        const tokenNonce = payload.nonce as string | undefined;
        if (!tokenNonce) {
          throw new Error('Apple identity token missing nonce claim');
        }
        if (expectedHash !== tokenNonce) {
          throw new Error('Nonce mismatch — possible replay attack');
        }
      }

      return {
        sub: payload.sub,
        email: payload.email as string | undefined,
        email_verified: payload.email_verified as boolean | undefined,
        real_user_status: payload.real_user_status as number | undefined,
      };
    } catch (err) {
      // Re-throw TimeoutError as-is (don't wrap in Apple-specific message)
      if (err instanceof TimeoutError) throw err;

      if (err instanceof joseErrors.JWTExpired) {
        throw new Error('Apple identity token has expired');
      }
      if (err instanceof joseErrors.JWSSignatureVerificationFailed) {
        throw new Error('Apple identity token signature verification failed');
      }
      throw new Error(`Apple token validation failed: ${(err as Error).message}`);
    }
  }

  // ── App JWT ─────────────────────────────────────────────────────────

  /**
   * Issue an app access JWT and refresh token pair.
   *
   * Access JWT claims:
   *   sub       — user_id UUID (from Lakebase auth.users)
   *   device_id — iOS Keychain device UUID
   *   platform  — "apple_healthkit" (extensible to Android, etc.)
   *   iat       — issued-at (auto-set by jose)
   *   exp       — iat + 900s (15 min)
   *
   * Signed with HS256 using JWT_SIGNING_SECRET from the Databricks secret
   * scope. The `sub` claim is the value written to the bronze table's
   * `user_id` column by extract-user.ts (Phase 2 integration).
   *
   * The refresh token is a cryptographically random opaque string. Only
   * its SHA-256 hash is stored in Lakebase — the raw token is returned
   * to the client and stored in the iOS Keychain.
   */
  async issueTokens(
    userId: string,
    deviceId: string,
    platform: string,
  ): Promise<AuthTokens> {
    if (!this.jwtSecret || !this.lakebase) {
      throw new Error('Auth service not initialized');
    }

    // ── Sign access JWT ───────────────────────────────────────────────
    const accessToken = await new SignJWT({
      device_id: deviceId,
      platform,
    })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setIssuedAt()
      .setExpirationTime(ACCESS_TOKEN_EXPIRY)
      .sign(this.jwtSecret);

    // ── Generate opaque refresh token ─────────────────────────────────
    const refreshToken = crypto.randomBytes(32).toString('base64url');
    const tokenHash = this.hashToken(refreshToken);

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + REFRESH_TOKEN_EXPIRY_DAYS);

    await this.query(
      `INSERT INTO auth.refresh_tokens (token_hash, user_id, device_id, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [tokenHash, userId, deviceId, expiresAt.toISOString()],
      'insert refresh token',
    );

    return {
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: ACCESS_TOKEN_EXPIRY_SECONDS,
      token_type: 'Bearer',
      user_id: userId,
    };
  }

  /**
   * Verify an app access JWT and return the decoded payload.
   *
   * Used by jwt-auth.ts middleware to authenticate incoming requests.
   * Throws TokenExpiredError (allows 401 with code TOKEN_EXPIRED) or a
   * generic Error for invalid tokens.
   */
  async verifyAccessToken(token: string): Promise<AccessTokenPayload> {
    if (!this.jwtSecret) {
      throw new Error('Auth service not initialized');
    }

    try {
      const { payload } = await jwtVerify(token, this.jwtSecret);

      if (!payload.sub) {
        throw new Error('Access token missing sub claim');
      }

      return {
        sub: payload.sub,
        device_id: payload.device_id as string,
        platform: payload.platform as string,
      };
    } catch (err) {
      if (err instanceof joseErrors.JWTExpired) {
        throw new TokenExpiredError('Access token has expired');
      }
      throw new Error(`Token verification failed: ${(err as Error).message}`);
    }
  }

  // ── Refresh Token ───────────────────────────────────────────────────

  /**
   * Exchange a refresh token for a new access JWT + refresh token pair.
   *
   * Implements token rotation (RFC 6819 5.2.2.3):
   *   1. Hash the presented token and look it up in Lakebase
   *   2. Verify it's not expired or revoked
   *   3. Revoke the old hash (set revoked_at)
   *   4. Issue a fresh token pair
   *
   * Token rotation limits the window of exposure if a refresh token is
   * intercepted. If a revoked token is presented, that's a signal of
   * potential theft — Phase 2 will add revoke-all-for-user in that case.
   */
  async refreshTokens(refreshToken: string): Promise<AuthTokens> {
    if (!this.lakebase) {
      throw new Error('Auth service not initialized');
    }

    const tokenHash = this.hashToken(refreshToken);

    const { rows } = await this.query(
      `SELECT user_id, device_id, expires_at, revoked_at
       FROM auth.refresh_tokens WHERE token_hash = $1`,
      [tokenHash],
      'lookup refresh token',
    );

    if (rows.length === 0) {
      throw new InvalidTokenError('Invalid refresh token');
    }

    const record = rows[0];

    if (record.revoked_at) {
      // Token reuse detected — potential theft.
      // Phase 1: reject. Phase 2: revoke all tokens for this user.
      logAuthEvent({
        event: 'token_reuse_detected',
        outcome: 'warn',
        userId: record.user_id as string,
        errorCode: 'TOKEN_REUSED',
        errorDetail: 'Revoked refresh token presented — possible token theft',
      });
      throw new TokenRevokedError('Refresh token has been revoked (possible token reuse)');
    }

    if (new Date(record.expires_at as string) < new Date()) {
      throw new TokenExpiredError('Refresh token has expired');
    }

    // Revoke the old refresh token (rotation)
    await this.query(
      `UPDATE auth.refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1`,
      [tokenHash],
      'revoke old refresh token',
    );

    // Update user last_seen_at
    await this.query(
      `UPDATE auth.users SET last_seen_at = NOW() WHERE user_id = $1`,
      [record.user_id],
      'update user last_seen_at',
    );

    // Issue new token pair
    return this.issueTokens(
      record.user_id as string,
      record.device_id as string,
      'apple_healthkit', // TODO: store platform in refresh_tokens for multi-platform
    );
  }

  /**
   * Revoke a refresh token (logout).
   *
   * The access JWT remains valid until its natural expiry (15 min) —
   * stateless by design. For immediate revocation, clients should also
   * discard the access token locally.
   *
   * Idempotent: revoking an already-revoked or nonexistent token
   * succeeds silently.
   */
  async revokeRefreshToken(refreshToken: string): Promise<void> {
    if (!this.lakebase) {
      throw new Error('Auth service not initialized');
    }

    const tokenHash = this.hashToken(refreshToken);

    const { rows } = await this.query(
      `UPDATE auth.refresh_tokens SET revoked_at = NOW()
       WHERE token_hash = $1 AND revoked_at IS NULL
       RETURNING token_hash`,
      [tokenHash],
      'revoke refresh token',
    );

    if (rows.length === 0) {
      logAuthEvent({
        event: 'token_revoke',
        outcome: 'warn',
        errorDetail: 'Token not found or already revoked',
      });
    }
  }

  // ── User Registry (Lakebase CRUD) ───────────────────────────────────

  /**
   * Create or update a user based on Apple's `sub` claim.
   *
   * On first sign-in, creates a new user with a generated UUID.
   * On subsequent sign-ins, updates last_seen_at and optionally the
   * display_name (Apple only provides the full name on the very first
   * authorization, so we use COALESCE to preserve the existing name).
   *
   * @returns user_id UUID — used as the `sub` claim in app JWTs
   */
  async upsertUser(appleSub: string, displayName?: string): Promise<string> {
    if (!this.lakebase) {
      throw new Error('Auth service not initialized');
    }

    const { rows } = await this.query(
      `INSERT INTO auth.users (apple_sub, display_name)
       VALUES ($1, $2)
       ON CONFLICT (apple_sub)
       DO UPDATE SET
         last_seen_at = NOW(),
         display_name = COALESCE(EXCLUDED.display_name, auth.users.display_name)
       RETURNING user_id`,
      [appleSub, displayName || null],
      'upsert user',
    );

    return rows[0].user_id as string;
  }

  /**
   * Register or update a device for a user.
   *
   * A single user may have multiple devices (iPhone + iPad + Apple Watch).
   * Each device is identified by its Keychain-persisted UUID
   * (DeviceIdentifier.current in the iOS app). The device_id is stable
   * across app updates but reset on reinstall.
   *
   * The ON CONFLICT clause handles device re-registration (e.g., after
   * the user signs out and back in, or when the same device is
   * transferred to a new Apple ID).
   */
  async registerDevice(
    userId: string,
    deviceId: string,
    platform: string,
    appVersion?: string,
  ): Promise<void> {
    if (!this.lakebase) {
      throw new Error('Auth service not initialized');
    }

    await this.query(
      `INSERT INTO auth.devices (device_id, user_id, platform, app_version)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (device_id)
       DO UPDATE SET
         user_id = EXCLUDED.user_id,
         platform = EXCLUDED.platform,
         app_version = COALESCE(EXCLUDED.app_version, auth.devices.app_version),
         last_seen_at = NOW()`,
      [deviceId, userId, platform, appVersion || null],
      'register device',
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /** SHA-256 hash of a refresh token for Lakebase storage. */
  private hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }
}

// ── Custom error classes ──────────────────────────────────────────────
//
// Distinct error types let route handlers and middleware map failures to
// the correct HTTP status codes and response shapes.

/** Access or refresh token has expired. Route handler returns 401 with code TOKEN_EXPIRED. */
export class TokenExpiredError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TokenExpiredError';
  }
}

/** Refresh token has been revoked (potential reuse/theft). Route handler returns 401. */
export class TokenRevokedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TokenRevokedError';
  }
}

/** Token is structurally invalid or not found. Route handler returns 401. */
export class InvalidTokenError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidTokenError';
  }
}

// ── Singleton export ──────────────────────────────────────────────────

export const authService = new AuthService();
