// Auth Logger — Structured JSON logging for auth events
//
// Emits machine-parseable JSON lines to console (picked up by the OTel
// log exporter configured in otel.ts). Every auth event becomes a single
// JSON object with standardized fields that OTel can index as log
// attributes.
//
// Privacy: All identifiers (user_id, device_id, apple_sub) are SHA-256
// hashed and truncated to 12 hex chars. This preserves correlation across
// log entries without storing raw PII. The hash prefix length (12 hex =
// 48 bits) gives a collision probability of ~1 in 281 trillion — more
// than sufficient for operational logging.
//
// Usage:
//   import { logAuthEvent } from '../../utils/auth-logger.js';
//
//   logAuthEvent({
//     event: 'apple_exchange',
//     outcome: 'success',
//     userId: rawUserId,
//     deviceId: rawDeviceId,
//     appleSub: rawAppleSub,
//     durationMs: Date.now() - start,
//   });

import crypto from 'node:crypto';

// ── Types ─────────────────────────────────────────────────────────────

export type AuthEventName =
  | 'apple_exchange'
  | 'token_refresh'
  | 'token_revoke'
  | 'service_init'
  | 'migration'
  | 'token_reuse_detected';

export type AuthOutcome = 'success' | 'failure' | 'warn';

export interface AuthLogEntry {
  /** Event type identifier (e.g. 'apple_exchange', 'token_refresh'). */
  event: AuthEventName;

  /** Outcome: success, failure, or warn. */
  outcome: AuthOutcome;

  /** Optional machine-readable error code (matches sanitized client codes). */
  errorCode?: string;

  /** Optional detailed error message (server-side only, never sent to client). */
  errorDetail?: string;

  /** Hashed before logging. Lakebase auth.users UUID. */
  userId?: string;

  /** Hashed before logging. iOS Keychain device UUID. */
  deviceId?: string;

  /** Hashed before logging. Apple's stable sub claim. */
  appleSub?: string;

  /** Request processing time in milliseconds. */
  durationMs?: number;

  /** Apple's real_user_status indicator (0/1/2). */
  realUserStatus?: number;

  /** Client-reported app version. */
  appVersion?: string;

  /** Platform string (e.g. 'apple_healthkit'). */
  platform?: string;

  /** Client IP from x-forwarded-for (for rate limit correlation). */
  clientIp?: string;

  /** Arbitrary extra fields for one-off context. */
  extra?: Record<string, unknown>;
}

// ── Hash helper ───────────────────────────────────────────────────────

/** SHA-256 hash truncated to 12 hex chars. Irreversible, collision-safe for logging. */
function hashId(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex').slice(0, 12);
}

// ── Logger ────────────────────────────────────────────────────────────

/**
 * Emit a structured JSON auth log entry.
 *
 * The output is a single JSON line written to the appropriate console
 * method (log for success, warn for warn, error for failure). The OTel
 * log exporter in otel.ts picks these up and forwards them to the
 * Databricks OTel collector, which writes to the _otel_logs table.
 *
 * All identifier fields are SHA-256 hashed before serialization.
 */
export function logAuthEvent(entry: AuthLogEntry): void {
  const record: Record<string, unknown> = {
    // ── Standard envelope ───────────────────────────────────────────
    logger: 'auth',
    event: entry.event,
    outcome: entry.outcome,
    ts: new Date().toISOString(),
  };

  // ── Error context ─────────────────────────────────────────────────
  if (entry.errorCode)   record.error_code   = entry.errorCode;
  if (entry.errorDetail) record.error_detail = entry.errorDetail;

  // ── Hashed identifiers ────────────────────────────────────────────
  if (entry.userId)   record.user_id_hash   = hashId(entry.userId);
  if (entry.deviceId) record.device_id_hash = hashId(entry.deviceId);
  if (entry.appleSub) record.apple_sub_hash = hashId(entry.appleSub);

  // ── Operational context ───────────────────────────────────────────
  if (entry.durationMs != null)     record.duration_ms      = entry.durationMs;
  if (entry.realUserStatus != null) record.real_user_status = entry.realUserStatus;
  if (entry.appVersion)             record.app_version      = entry.appVersion;
  if (entry.platform)               record.platform         = entry.platform;
  if (entry.clientIp)               record.client_ip        = entry.clientIp;

  // ── Extra (pass-through) ──────────────────────────────────────────
  if (entry.extra) {
    for (const [k, v] of Object.entries(entry.extra)) {
      record[k] = v;
    }
  }

  // ── Emit ──────────────────────────────────────────────────────────
  const json = JSON.stringify(record);

  switch (entry.outcome) {
    case 'success':
      console.log(json);
      break;
    case 'warn':
      console.warn(json);
      break;
    case 'failure':
      console.error(json);
      break;
  }
}

/**
 * Get the client IP from an Express request.
 * Uses x-forwarded-for (set by the AppKit auth sidecar proxy) or falls
 * back to req.ip.
 */
export function getClientIp(req: { headers: Record<string, string | string[] | undefined>; ip?: string }): string {
  const xff = req.headers['x-forwarded-for'];
  if (typeof xff === 'string') return xff.split(',')[0].trim();
  if (Array.isArray(xff) && xff.length > 0) return xff[0].split(',')[0].trim();
  return req.ip || 'unknown';
}
