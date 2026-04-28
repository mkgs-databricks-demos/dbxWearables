// JWT Authentication Middleware
//
// Validates app-issued JWTs and populates req.auth with decoded claims.
// Used by auth-routes.ts (protecting /revoke) and ingest-routes.ts
// (user identity attribution for mobile clients).
//
// Two modes:
//   requireAuth  — returns 401 if no valid token is present
//   optionalAuth — attaches user info if present, continues without error if missing
//
// Token sources (checked in order):
//   1. req.auth (already set by SPN route guard — skip re-verification)
//   2. Authorization: Bearer <token> (direct JWT or workspace user)
//   3. X-User-JWT: <token> (user identity envelope for SPN-authenticated
//      mobile requests — the SPN token goes in Authorization for sidecar
//      auth, and the app JWT rides in this custom header)
//
// Request augmentation:
//   On successful validation, req.auth is populated with the decoded
//   AccessTokenPayload (sub, device_id, platform). Downstream handlers
//   use req.auth.sub as the authenticated user_id.
//
// Integration with SPN Route Guard:
//   The route guard (spn-route-guard.ts) may have already validated the
//   Bearer token and populated req.auth. If req.auth is already set,
//   this middleware skips verification to avoid redundant work.
//
// Error responses:
//   401 { status: "error", message: "...", code?: "TOKEN_EXPIRED" }
//   503 { status: "error", message: "Authentication service not available" }

import type { Request, Response, NextFunction } from 'express';
import { authService, TokenExpiredError } from '../services/auth-service.js';
import type { AccessTokenPayload } from '../services/auth-service.js';

// ── Extend Express Request type ───────────────────────────────────────
//
// Adds the optional `auth` property to all Express Request objects.
// When JWT middleware validates a token, this contains the decoded claims.
// When no middleware runs or the token is absent (optionalAuth), it's undefined.
//
// NOTE: The `auth` property may also be set by spn-route-guard.ts, which
// validates Bearer tokens during caller identification. The declaration
// here is compatible — both middlewares set the same type.

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      /** Decoded JWT claims — set by requireAuth / optionalAuth / route guard. */
      auth?: AccessTokenPayload;
    }
  }
}

// ── Middleware exports ───────────────────────────────────────────────

/**
 * Required JWT authentication middleware.
 * Returns 401 if no valid Bearer token is present.
 *
 * Usage:
 *   app.post('/api/v1/auth/revoke', requireAuth, handler);
 *   // handler can access req.auth.sub, req.auth.device_id, etc.
 */
export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  void authenticateRequest(req, res, next, true);
}

/**
 * Optional JWT authentication middleware.
 * Attaches user info if a valid token is present, but allows
 * unauthenticated requests to proceed.
 *
 * Checks Authorization header first, then X-User-JWT header.
 * The X-User-JWT header is used by SPN-authenticated mobile clients
 * that send the SPN OAuth token in Authorization (for sidecar auth)
 * and the app JWT in X-User-JWT (for user identity).
 *
 * Usage:
 *   app.post('/api/v1/healthkit/ingest', optionalAuth, handler);
 *   // handler checks req.auth?.sub — falls back to x-forwarded-email or 'anonymous'
 */
export function optionalAuth(req: Request, res: Response, next: NextFunction): void {
  void authenticateRequest(req, res, next, false);
}

// ── Implementation ──────────────────────────────────────────────────

async function authenticateRequest(
  req: Request,
  res: Response,
  next: NextFunction,
  required: boolean,
): Promise<void> {
  // ── Short-circuit: route guard already validated the token ──────
  //
  // The SPN route guard (spn-route-guard.ts) validates Bearer tokens
  // during caller identification and populates req.auth. If it's already
  // set, skip re-verification — the token was already validated.
  if (req.auth) {
    next();
    return;
  }

  // ── Guard: auth service must be initialized ─────────────────────
  if (!authService.isReady()) {
    if (required) {
      res.status(503).json({
        status: 'error',
        message: 'Authentication service not available',
      });
      return;
    }
    next();
    return;
  }

  // ── Source 1: Authorization Bearer token ─────────────────────────
  const authHeader = req.headers['authorization'];
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    const result = await tryVerifyToken(token);
    if (result.ok) {
      req.auth = result.payload;
      next();
      return;
    }
    // For required auth, reject on expired token from Authorization header
    if (required && result.expired) {
      res.status(401).json({
        status: 'error',
        message: 'Access token expired',
        code: 'TOKEN_EXPIRED',
      });
      return;
    }
    if (required && result.invalid) {
      // Don't reject yet — fall through to check X-User-JWT.
      // The Authorization header might be a SPN OAuth token (not our JWT).
    }
  }

  // ── Source 2: X-User-JWT header ─────────────────────────────────
  //
  // SPN-authenticated mobile requests carry the Databricks SPN OAuth
  // token in Authorization (for sidecar auth) and the app-issued JWT
  // in X-User-JWT (for user identity). The sidecar strips/replaces
  // Authorization but passes through custom headers untouched.
  const userJwtHeader = req.headers['x-user-jwt'];
  if (typeof userJwtHeader === 'string' && userJwtHeader.length > 0) {
    const result = await tryVerifyToken(userJwtHeader);
    if (result.ok) {
      req.auth = result.payload;
      next();
      return;
    }
    // X-User-JWT present but invalid/expired — log for visibility
    if (result.expired) {
      console.warn('[JWT] X-User-JWT token expired');
      if (required) {
        res.status(401).json({
          status: 'error',
          message: 'User JWT expired',
          code: 'TOKEN_EXPIRED',
        });
        return;
      }
    } else {
      console.warn('[JWT] X-User-JWT token invalid');
    }
  }

  // ── No valid token found ───────────────────────────────────────
  if (required) {
    res.status(401).json({
      status: 'error',
      message: 'Missing or invalid authentication. Send app JWT in Authorization or X-User-JWT header.',
    });
    return;
  }

  // Optional auth — continue without user info
  next();
}

// ── Token verification helper ───────────────────────────────────────

type VerifyResult =
  | { ok: true; payload: AccessTokenPayload; expired?: false; invalid?: false }
  | { ok: false; payload?: undefined; expired: boolean; invalid: boolean };

async function tryVerifyToken(token: string): Promise<VerifyResult> {
  try {
    const payload = await authService.verifyAccessToken(token);
    return { ok: true, payload };
  } catch (err) {
    if (err instanceof TokenExpiredError) {
      return { ok: false, expired: true, invalid: false };
    }
    return { ok: false, expired: false, invalid: true };
  }
}
