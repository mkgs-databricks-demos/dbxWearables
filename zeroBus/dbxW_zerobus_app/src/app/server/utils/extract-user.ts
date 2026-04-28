// Shared User Identity Extraction
//
// Extracts user identity from incoming HTTP requests — priority-ordered,
// 3-way branch. Used by both the real HealthKit ingest routes and the
// synthetic load test routes to ensure consistent user_id attribution.
//
// The user_id value flows into the bronze table's `user_id` column via
// zeroBusService.buildRecord(). It is the join key for associating
// wearable data with authenticated users in silver/gold layers.
//
// ── Authentication pipeline (runs BEFORE this function) ───────────────
//
//   1. spn-route-guard.ts (global middleware on /api/*)
//      Classifies caller type (workspace-user, ios-spn, etc.).
//      For direct app-jwt-user requests, validates the Bearer JWT
//      and populates req.auth.
//
//   2. optionalAuth middleware (on ingest route, defense-in-depth)
//      Checks two JWT sources in order:
//        a) Authorization: Bearer <token> (direct JWT access)
//        b) X-User-JWT: <token> (SPN-authenticated mobile requests
//           where Authorization carries the Databricks SPN OAuth
//           token for sidecar auth, and the app-issued JWT rides
//           in this custom header for user identity)
//      Short-circuits if req.auth is already set (by route guard).
//
// By the time extractUser() runs, req.auth is populated for any
// request with a valid app-issued JWT (from either header source).
// This function simply reads the validated result — it does NOT
// perform JWT validation itself.

import type { Request } from 'express';

/**
 * Extract user identity — priority-ordered, 3-way branch.
 *
 * 1. req.auth?.sub (app-issued JWT, validated by route guard / optionalAuth)
 *    The `sub` claim is the Lakebase auth.users `user_id` UUID, set when
 *    the user first signed in via Apple. This is the canonical user_id
 *    for mobile clients — stable, privacy-preserving, and tied to the
 *    Apple Sign In identity.
 *
 *    The JWT may arrive via:
 *      - Authorization: Bearer <app-jwt> (direct mobile access)
 *      - X-User-JWT: <app-jwt> (SPN-authenticated mobile request;
 *        Authorization carries the Databricks SPN token for sidecar
 *        auth, and the app JWT is in this custom header)
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
  // ── Branch 1: App-authenticated user (validated JWT) ────────────
  //
  // req.auth is populated by the SPN route guard (all /api/* routes)
  // or the optionalAuth middleware (ingest route). The sub claim is
  // the Lakebase user_id UUID from auth.users.
  if (req.auth?.sub) {
    return req.auth.sub;
  }

  // ── Branch 2: Workspace traffic via AppKit proxy ────────────────
  const email = req.headers['x-forwarded-email'];
  if (typeof email === 'string' && email.length > 0) {
    return email;
  }

  // ── Branch 3: No auth context ───────────────────────────────
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
