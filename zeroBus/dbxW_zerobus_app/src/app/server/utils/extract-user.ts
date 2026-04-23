// Shared User Identity Extraction
//
// Extracts user identity from incoming HTTP requests — priority-ordered,
// 3-way branch. Used by both the real HealthKit ingest routes and the
// synthetic load test routes to ensure consistent user_id attribution.

import type { Request } from 'express';

/**
 * Extract user identity — priority-ordered, 3-way branch.
 *
 * 1. Authorization: Bearer <token>
 *    If present, the request came directly from a mobile client (iOS/
 *    Android) — AppKit's proxy strips this header for workspace traffic.
 *    TODO: validate app-issued JWT signature, check expiry, extract
 *    `sub` claim (Lakebase users.user_id UUID). Until JWT validation is
 *    implemented, the token is logged but not trusted → 'anonymous'.
 *
 * 2. x-forwarded-email
 *    Workspace traffic (notebook, job, service). Injected by AppKit's
 *    reverse proxy after OAuth validation. Trustworthy — proxy strips
 *    any client-supplied x-forwarded-* headers before injecting its own.
 *    Value: user email (e.g. "matthew.giglia@databricks.com"), matches
 *    Spark SQL current_user().
 *
 * 3. Neither → 'anonymous'
 *    No authentication context. Pre-auth clients, health checks, or
 *    development/testing.
 */
export function extractUser(req: Request): string {
  // ── Branch 1: Direct client with Bearer token (mobile app) ──────
  const authHeader = req.headers['authorization'];
  if (typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
    // TODO: Replace this placeholder with real JWT validation:
    //   1. Verify signature against app secret (from dbxw_zerobus_secrets scope)
    //   2. Check exp claim (reject expired tokens)
    //   3. Extract sub claim → Lakebase users.user_id UUID
    //   4. Return the UUID as user_id
    console.info(
      '[Auth] Bearer token received — JWT validation not yet implemented, user_id set to anonymous',
    );
    return 'anonymous';
  }

  // ── Branch 2: Workspace traffic via AppKit proxy ────────────────
  const email = req.headers['x-forwarded-email'];
  if (typeof email === 'string' && email.length > 0) {
    return email;
  }

  // ── Branch 3: No auth context ───────────────────────────────────
  return 'anonymous';
}

/**
 * Extract the client IP address from the request.
 * AppKit proxy sets x-forwarded-for; falls back to req.ip.
 */
export function extractClientIp(req: Request): string {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string') {
    return forwarded.split(',')[0].trim();
  }
  return req.ip ?? 'unknown';
}
