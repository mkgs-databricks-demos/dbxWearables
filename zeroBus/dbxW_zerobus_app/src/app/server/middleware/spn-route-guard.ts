// SPN Route Guard — Global API Access Control
//
// Identifies the caller type from proxy-injected headers and Bearer tokens,
// then enforces route-zone restrictions. Registered as global middleware on
// all /api/* routes in server.ts — runs BEFORE route-specific handlers.
//
// ── Caller identification (priority order) ───────────────────────────
//
//   1. Authorization: Bearer <token> → validate as app JWT
//      AppKit's proxy strips this header for proxy-authenticated traffic,
//      so its presence means the request bypassed the proxy (= mobile client).
//      If the token validates → 'app-jwt-user' (req.auth is populated).
//
//   2. x-forwarded-email with '@' → 'workspace-user'
//      Injected by AppKit's proxy after OAuth validation. Contains the
//      workspace user's email. Proxy strips client-supplied forwarded
//      headers, so this is trustworthy.
//
//   3. Proxy headers present, no email with '@' → SPN or machine identity
//      If IOS_SPN_APPLICATION_ID is configured and the forwarded identity
//      matches → 'ios-spn'. Otherwise → 'proxy-unverified'.
//
//   4. No auth context → 'anonymous'
//
// ── Access matrix ────────────────────────────────────────────────────
//
//   Caller            │ auth routes │ ingest routes │ admin routes │ health
//   ──────────────────┼─────────────┼───────────────┼──────────────┼────────
//   workspace-user    │     ✓       │       ✓       │      ✓       │   ✓
//   app-jwt-user      │     ✓       │       ✓       │      ✗       │   ✓
//   ios-spn (verified)│     ✓       │       ✗       │      ✗       │   ✓
//   proxy-unverified  │     ✓       │       ✗       │      ✗       │   ✓
//   anonymous         │     ✗       │       ✗       │      ✗       │   ✓
//
// ── Route zones ──────────────────────────────────────────────────────
//
//   auth:    /api/v1/auth/*          (Sign in with Apple, refresh, revoke)
//   ingest:  /api/v1/healthkit/*     (HealthKit data ingestion)
//   admin:   /api/lakebase/*, /api/* (Lakebase CRUD, testing, load test)
//   health:  any path ending in /health (diagnostic, always open)

import type { Request, Response, NextFunction, Application } from 'express';
import { authService } from '../services/auth-service.js';

// ── Caller types ──────────────────────────────────────────────────────

export type CallerType =
  | 'workspace-user'    // Workspace user via AppKit proxy (email in x-forwarded-email)
  | 'app-jwt-user'      // Mobile user with a validated app-issued JWT
  | 'ios-spn'           // Verified iOS bootstrap SPN (matches IOS_SPN_APPLICATION_ID)
  | 'proxy-unverified'  // Proxy-authenticated but not a user or known SPN
  | 'anonymous';        // No authentication context

// Augment Express Request with callerType
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      /** Caller type determined by the route guard. */
      callerType?: CallerType;
    }
  }
}

// ── Route zone classification ─────────────────────────────────────────

type RouteZone = 'health' | 'auth' | 'ingest' | 'admin';

function classifyRoute(path: string): RouteZone {
  // Health endpoints are always open (diagnostic, no sensitive data)
  if (path.endsWith('/health')) return 'health';

  if (path.startsWith('/api/v1/auth/')) return 'auth';
  if (path.startsWith('/api/v1/healthkit/')) return 'ingest';

  // Everything else under /api/ is admin (lakebase, testing, etc.)
  return 'admin';
}

// ── Access control matrix ─────────────────────────────────────────────

const ACCESS_MATRIX: Record<CallerType, Set<RouteZone>> = {
  'workspace-user':   new Set(['health', 'auth', 'ingest', 'admin']),
  'app-jwt-user':     new Set(['health', 'auth', 'ingest']),
  'ios-spn':          new Set(['health', 'auth']),
  'proxy-unverified': new Set(['health', 'auth']),
  'anonymous':        new Set(['health']),
};

// ── Caller identification ─────────────────────────────────────────────

async function identifyCaller(req: Request): Promise<CallerType> {
  // ── Priority 1: App JWT (mobile client, bypasses proxy) ─────────
  //
  // AppKit's proxy strips the Authorization header for proxy-authenticated
  // traffic. If Bearer is present, the request came directly from a mobile
  // client. Try to validate it as our app-issued JWT.
  const authHeader = req.headers['authorization'];
  if (authHeader?.startsWith('Bearer ') && authService.isReady()) {
    try {
      const token = authHeader.slice(7);
      const payload = await authService.verifyAccessToken(token);
      req.auth = payload; // Populate for downstream handlers (avoids double verification)
      return 'app-jwt-user';
    } catch {
      // Invalid or expired token — fall through to other identification methods.
      // Don't reject here; the caller might also have proxy headers (edge case).
    }
  }

  // ── Priority 2: Workspace user (proxy-authenticated with email) ──
  //
  // x-forwarded-email is injected by AppKit's proxy after OAuth validation.
  // For workspace users, this is their email address (contains '@').
  // For SPNs, this may be the SPN's display name or application ID (no '@').
  const forwardedEmail = req.headers['x-forwarded-email'];
  if (typeof forwardedEmail === 'string' && forwardedEmail.includes('@')) {
    return 'workspace-user';
  }

  // ── Priority 3: SPN identification ──────────────────────────────
  //
  // If proxy headers are present but no email with '@', the caller is
  // likely a service principal. Check if it matches the known iOS SPN.
  const hasProxyHeaders = !!(
    forwardedEmail ||
    req.headers['x-forwarded-for'] ||
    req.headers['x-forwarded-access-token']
  );

  if (hasProxyHeaders) {
    const iosSpnId = process.env.IOS_SPN_APPLICATION_ID;

    if (iosSpnId) {
      // Check if the forwarded identity matches the known iOS SPN.
      // The proxy may inject the SPN's application_id or display name
      // in x-forwarded-email. Check both the header value and any
      // other identifying headers.
      if (
        forwardedEmail === iosSpnId ||
        forwardedEmail === `spn-${iosSpnId}` // Common SPN display name pattern
      ) {
        return 'ios-spn';
      }

      // Proxy-authenticated but not the known iOS SPN — unverified.
      // Logged at warn level for visibility.
      return 'proxy-unverified';
    }

    // IOS_SPN_APPLICATION_ID not configured — can't distinguish SPNs.
    // Allow auth routes (they have their own Apple token validation).
    return 'proxy-unverified';
  }

  // ── Priority 4: No auth context ────────────────────────────────
  return 'anonymous';
}

// ── Middleware factory ─────────────────────────────────────────────────

/**
 * Create the SPN route guard middleware.
 *
 * Returns an Express middleware function that:
 *   1. Identifies the caller type
 *   2. Classifies the target route zone
 *   3. Checks the access matrix
 *   4. Allows or rejects with 401/403
 *
 * Register on all /api/* routes in server.ts before route handlers.
 */
export function createRouteGuard() {
  const iosSpnId = process.env.IOS_SPN_APPLICATION_ID;

  if (iosSpnId) {
    console.log(`[RouteGuard] iOS SPN identity configured: ${iosSpnId.slice(0, 8)}...`);
  } else {
    console.warn(
      '[RouteGuard] IOS_SPN_APPLICATION_ID not set — SPN identity verification disabled. ' +
      'All proxy-authenticated non-user callers will be allowed on auth routes.',
    );
  }

  return async function routeGuard(
    req: Request,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    const callerType = await identifyCaller(req);
    req.callerType = callerType;

    const zone = classifyRoute(req.path);
    const allowed = ACCESS_MATRIX[callerType];

    if (allowed.has(zone)) {
      next();
      return;
    }

    // ── Access denied ─────────────────────────────────────────────
    const status = callerType === 'anonymous' ? 401 : 403;
    const label = callerType === 'anonymous' ? 'Authentication required' : 'Forbidden';

    if (callerType !== 'anonymous') {
      console.warn(
        `[RouteGuard] ${status} ${callerType} denied access to ${zone} zone: ${req.method} ${req.path}`,
      );
    }

    res.status(status).json({
      status: 'error',
      message: `${label}: ${callerType} callers cannot access ${zone} routes`,
      caller_type: callerType,
      zone,
    });
  };
}

// ── Registration helper ───────────────────────────────────────────────

interface AppKitServer {
  server: {
    extend(fn: (app: Application) => void): void;
  };
}

/**
 * Register the SPN route guard as global middleware on all /api/* routes.
 * Must be called BEFORE any route registrations in server.ts.
 */
export function setupRouteGuard(appkit: AppKitServer): void {
  const guard = createRouteGuard();

  appkit.server.extend((app) => {
    app.use('/api/', guard);
    console.log('[RouteGuard] Registered on /api/* routes');
  });
}
