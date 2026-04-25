// Auth Routes — Sign in with Apple JWT Authentication
//
// POST /api/v1/auth/apple   — Exchange Apple identity token for app JWT
// POST /api/v1/auth/refresh — Silent token renewal (rotate refresh token)
// POST /api/v1/auth/revoke  — Logout (revoke refresh token)
// GET  /api/v1/auth/health  — Auth subsystem health check
//
// These endpoints implement the "User -> App" authentication layer
// documented in SecurityPage.tsx. Users authenticate to the app via
// Sign in with Apple; the app authenticates to Databricks via M2M
// service principal credentials (separate layer, platform-managed).
//
// Request/response contracts are designed to be compatible with the
// iOS app's APIResponse.swift decoder (unknown keys are ignored).
//
// Rate limiting: each mutable endpoint has an in-memory rate limiter
// keyed on client IP (from x-forwarded-for). Limits are tuned for
// expected mobile client usage patterns:
//   /apple  — 10 per 15 min (bootstrap is infrequent)
//   /refresh — 20 per 1 min (handles multi-device)
//   /revoke — 10 per 1 min (logout is infrequent)
//
// See auth-service.ts for the core authentication logic.
// See spn-route-guard.ts for route-level access control.

import type { Application, Request, Response } from 'express';
import { authService } from '../../services/auth-service.js';
import { requireAuth } from '../../middleware/jwt-auth.js';
import {
  authAppleLimiter,
  authRefreshLimiter,
  authRevokeLimiter,
} from '../../middleware/rate-limit.js';

// ── AppKit interface (only the server plugin is needed) ────────────────

interface AppKitServer {
  server: {
    extend(fn: (app: Application) => void): void;
  };
}

// ── Route registration ─────────────────────────────────────────────────

export async function setupAuthRoutes(appkit: AppKitServer) {
  if (!authService.isReady()) {
    console.warn(
      '[Auth] Auth service not ready — auth routes will return 503 until ' +
      'JWT_SIGNING_SECRET is provisioned in the secret scope',
    );
  }

  // Create rate limiter instances (each has its own counter store)
  const appleLimiter = authAppleLimiter();
  const refreshLimiter = authRefreshLimiter();
  const revokeLimiter = authRevokeLimiter();

  appkit.server.extend((app) => {

    // ── POST /api/v1/auth/apple ──────────────────────────────────────
    //
    // Exchange an Apple identity token for app credentials.
    //
    // Flow:
    //   1. Validate Apple JWT (JWKS signature + iss/aud/exp claims)
    //   2. Extract `sub` claim (Apple's privacy-preserving user ID)
    //   3. Upsert user in Lakebase (keyed on apple_sub)
    //   4. Register device (keyed on device_id from iOS Keychain)
    //   5. Issue app JWT (15 min) + refresh token (30 days)
    //
    // Request:
    //   { identity_token: string, device_id: string,
    //     platform?: string, app_version?: string }
    //
    // Response (200):
    //   { access_token, refresh_token, expires_in, token_type, user_id }
    //
    // Rate limit: 10 per 15 min per IP
    // Errors: 400 (missing fields), 401 (Apple validation failed),
    //         429 (rate limited), 503 (not initialized)

    app.post('/api/v1/auth/apple', appleLimiter, async (req: Request, res: Response) => {
      if (!authService.isReady()) {
        res.status(503).json({
          status: 'error',
          message: 'Auth service not available — JWT_SIGNING_SECRET not provisioned',
        });
        return;
      }

      try {
        const { identity_token, device_id, platform, app_version } = req.body || {};

        // ── Validate required fields ──────────────────────────────────
        if (!identity_token || typeof identity_token !== 'string') {
          res.status(400).json({
            status: 'error',
            message: 'Missing required field: identity_token (Apple identity JWT from ASAuthorizationAppleIDCredential)',
          });
          return;
        }

        if (!device_id || typeof device_id !== 'string') {
          res.status(400).json({
            status: 'error',
            message: 'Missing required field: device_id (DeviceIdentifier.current from iOS Keychain)',
          });
          return;
        }

        // ── Validate Apple identity token ─────────────────────────────
        const applePayload = await authService.validateAppleToken(identity_token);

        // ── Upsert user (keyed on Apple's sub claim) ──────────────────
        const userId = await authService.upsertUser(
          applePayload.sub,
          undefined, // display_name — only available on first auth via fullName credential
        );

        // ── Register device ───────────────────────────────────────────
        await authService.registerDevice(
          userId,
          device_id,
          platform || 'apple_healthkit',
          app_version,
        );

        // ── Issue tokens ──────────────────────────────────────────────
        const tokens = await authService.issueTokens(
          userId,
          device_id,
          platform || 'apple_healthkit',
        );

        console.log(
          `[Auth] Apple sign-in: user=${userId} device=${device_id} ` +
          `apple_sub=${applePayload.sub.slice(0, 8)}...`,
        );

        res.status(200).json(tokens);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error('[Auth] Apple auth failed:', message);

        // Distinguish Apple validation errors (401) from server errors (500)
        const isValidationError =
          message.includes('Apple') || message.includes('token') || message.includes('audience');

        res.status(isValidationError ? 401 : 500).json({
          status: 'error',
          message: isValidationError ? message : 'Authentication failed',
        });
      }
    });

    // ── POST /api/v1/auth/refresh ────────────────────────────────────
    //
    // Exchange a refresh token for new credentials.
    // Implements token rotation: old refresh token is revoked, new one issued.
    //
    // This is a public endpoint (no access JWT required) because the
    // primary use case is renewing an expired access token.
    //
    // Rate limit: 20 per 1 min per IP

    app.post('/api/v1/auth/refresh', refreshLimiter, async (req: Request, res: Response) => {
      if (!authService.isReady()) {
        res.status(503).json({
          status: 'error',
          message: 'Auth service not available',
        });
        return;
      }

      try {
        const { refresh_token } = req.body || {};

        if (!refresh_token || typeof refresh_token !== 'string') {
          res.status(400).json({
            status: 'error',
            message: 'Missing required field: refresh_token',
          });
          return;
        }

        const tokens = await authService.refreshTokens(refresh_token);

        console.log(`[Auth] Token refreshed: user=${tokens.user_id}`);
        res.status(200).json(tokens);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error('[Auth] Refresh failed:', message);

        // All refresh failures are 401 — the client should re-authenticate
        res.status(401).json({
          status: 'error',
          message,
          // Help the client distinguish "re-auth needed" from "try again later"
          ...(message.includes('expired') && { code: 'TOKEN_EXPIRED' }),
          ...(message.includes('revoked') && { code: 'TOKEN_REVOKED' }),
        });
      }
    });

    // ── POST /api/v1/auth/revoke ─────────────────────────────────────
    //
    // Revoke a refresh token (logout).
    // Requires a valid access JWT to prevent unauthorized revocation.
    //
    // Rate limit: 10 per 1 min per IP

    app.post('/api/v1/auth/revoke', revokeLimiter, requireAuth, async (req: Request, res: Response) => {
      if (!authService.isReady()) {
        res.status(503).json({
          status: 'error',
          message: 'Auth service not available',
        });
        return;
      }

      try {
        const { refresh_token } = req.body || {};

        if (!refresh_token || typeof refresh_token !== 'string') {
          res.status(400).json({
            status: 'error',
            message: 'Missing required field: refresh_token',
          });
          return;
        }

        await authService.revokeRefreshToken(refresh_token);

        console.log(`[Auth] Token revoked: user=${req.auth?.sub}`);
        res.status(200).json({
          status: 'success',
          message: 'Token revoked',
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error('[Auth] Revoke failed:', message);

        res.status(500).json({
          status: 'error',
          message: 'Token revocation failed',
        });
      }
    });

    // ── GET /api/v1/auth/health ──────────────────────────────────────
    //
    // Health check for the auth subsystem.
    // Reports initialization state, env var presence, and route guard config.

    app.get('/api/v1/auth/health', (_req: Request, res: Response) => {
      res.json({
        status: authService.isReady() ? 'ok' : 'not_initialized',
        service: 'jwt-auth',
        env_configured: {
          JWT_SIGNING_SECRET: !!process.env.JWT_SIGNING_SECRET,
          APPLE_BUNDLE_ID: !!process.env.APPLE_BUNDLE_ID,
          IOS_SPN_APPLICATION_ID: !!process.env.IOS_SPN_APPLICATION_ID,
        },
        hardening: {
          route_guard: true,
          rate_limiting: true,
          spn_identity_verification: !!process.env.IOS_SPN_APPLICATION_ID,
        },
      });
    });
  });
}
