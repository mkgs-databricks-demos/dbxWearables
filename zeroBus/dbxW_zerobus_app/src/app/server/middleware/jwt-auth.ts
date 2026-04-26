// JWT Authentication Middleware
//
// Extracts and validates Bearer tokens from the Authorization header.
// Used by auth-routes.ts (protecting /revoke) and will be used by
// ingest-routes.ts in Phase 2 to validate mobile client identity.
//
// Two modes:
//   requireAuth  — returns 401 if token is missing or invalid
//   optionalAuth — attaches user info if present, continues without error if missing
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

// ── Middleware exports ─────────────────────────────────────────────────

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
 * Usage (Phase 2 — ingest route):
 *   app.post('/api/v1/healthkit/ingest', optionalAuth, handler);
 *   // handler checks req.auth?.sub — falls back to x-forwarded-email or 'anonymous'
 */
export function optionalAuth(req: Request, res: Response, next: NextFunction): void {
  void authenticateRequest(req, res, next, false);
}

// ── Implementation ────────────────────────────────────────────────────

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

  // ── Extract Bearer token ────────────────────────────────────────
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    if (required) {
      res.status(401).json({
        status: 'error',
        message: 'Missing or invalid Authorization header. Expected: Bearer <token>',
      });
      return;
    }
    next();
    return;
  }

  const token = authHeader.slice(7); // Remove 'Bearer ' prefix

  // ── Verify token ────────────────────────────────────────────────
  try {
    const payload = await authService.verifyAccessToken(token);
    req.auth = payload;
    next();
  } catch (err) {
    if (err instanceof TokenExpiredError) {
      if (required) {
        res.status(401).json({
          status: 'error',
          message: 'Access token expired',
          code: 'TOKEN_EXPIRED',
        });
        return;
      }
      // Optional: expired token = no auth, continue
      next();
      return;
    }

    if (required) {
      res.status(401).json({
        status: 'error',
        message: 'Invalid access token',
      });
      return;
    }

    // Optional auth — continue without user info
    next();
  }
}
