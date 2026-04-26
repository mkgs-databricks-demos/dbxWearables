// In-Memory Rate Limiter — Sliding Window Counter
//
// Factory function that creates Express middleware for rate-limiting
// specific routes. Uses a fixed-window counter with automatic cleanup
// to prevent memory leaks.
//
// Designed for single-instance Databricks Apps where in-memory state is
// sufficient. For multi-instance deployments, migrate to Lakebase-backed
// counters (same interface, different storage backend).
//
// Standard rate limit headers are set on every response:
//   X-RateLimit-Limit     — max requests per window
//   X-RateLimit-Remaining — requests remaining in current window
//   X-RateLimit-Reset     — Unix timestamp when the window resets
//   Retry-After           — seconds until the window resets (429 only)
//
// Usage:
//   import { createRateLimiter } from '../middleware/rate-limit.js';
//
//   const authAppleLimiter = createRateLimiter({
//     windowMs: 15 * 60 * 1000,  // 15 minutes
//     maxRequests: 10,
//     message: 'Too many sign-in attempts',
//   });
//
//   app.post('/api/v1/auth/apple', authAppleLimiter, handler);

import type { Request, Response, NextFunction } from 'express';

// ── Configuration ─────────────────────────────────────────────────────

export interface RateLimitConfig {
  /** Time window in milliseconds. */
  windowMs: number;
  /** Maximum requests allowed per window per key. */
  maxRequests: number;
  /** Custom error message (default: 'Too many requests'). */
  message?: string;
  /**
   * Extract the rate limit key from the request.
   * Default: client IP from x-forwarded-for or req.ip.
   */
  keyExtractor?: (req: Request) => string;
  /**
   * Whether to include the rate limit headers on non-429 responses.
   * Default: true.
   */
  includeHeaders?: boolean;
}

// ── Internal state ────────────────────────────────────────────────────

interface WindowEntry {
  count: number;
  resetAt: number;  // Unix timestamp (ms) when this window expires
}

/** Minimum interval between cleanup sweeps (ms). */
const CLEANUP_INTERVAL_MS = 60_000;

// ── Default key extractor ─────────────────────────────────────────────

/**
 * Extract client IP from the request.
 * Uses x-forwarded-for (set by AppKit proxy) with fallback to req.ip.
 */
function defaultKeyExtractor(req: Request): string {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string') {
    return forwarded.split(',')[0].trim();
  }
  return req.ip ?? 'unknown';
}

// ── Factory ───────────────────────────────────────────────────────────

/**
 * Create a rate limiter middleware.
 *
 * Each call creates an independent counter store — use one limiter per
 * endpoint (or group of endpoints that share a budget).
 */
export function createRateLimiter(config: RateLimitConfig) {
  const {
    windowMs,
    maxRequests,
    message = 'Too many requests',
    keyExtractor = defaultKeyExtractor,
    includeHeaders = true,
  } = config;

  const store = new Map<string, WindowEntry>();
  let lastCleanup = Date.now();

  // ── Periodic cleanup of expired entries ──────────────────────────
  function cleanup(): void {
    const now = Date.now();
    if (now - lastCleanup < CLEANUP_INTERVAL_MS) return;

    lastCleanup = now;
    let removed = 0;
    for (const [key, entry] of store) {
      if (entry.resetAt <= now) {
        store.delete(key);
        removed++;
      }
    }
    if (removed > 0) {
      console.log(`[RateLimit] Cleaned up ${removed} expired entries (${store.size} remaining)`);
    }
  }

  // ── Middleware ───────────────────────────────────────────────────
  return function rateLimitMiddleware(
    req: Request,
    res: Response,
    next: NextFunction,
  ): void {
    cleanup();

    const key = keyExtractor(req);
    const now = Date.now();

    let entry = store.get(key);

    // Start a new window if none exists or the current one expired
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      store.set(key, entry);
    }

    entry.count++;

    const remaining = Math.max(0, maxRequests - entry.count);
    const resetTimestamp = Math.ceil(entry.resetAt / 1000); // Unix seconds

    // Set rate limit headers on all responses (not just 429)
    if (includeHeaders) {
      res.setHeader('X-RateLimit-Limit', maxRequests);
      res.setHeader('X-RateLimit-Remaining', remaining);
      res.setHeader('X-RateLimit-Reset', resetTimestamp);
    }

    // ── Over limit → 429 ──────────────────────────────────────────
    if (entry.count > maxRequests) {
      const retryAfterSeconds = Math.ceil((entry.resetAt - now) / 1000);
      res.setHeader('Retry-After', retryAfterSeconds);

      console.warn(
        `[RateLimit] 429 for key=${key} (${entry.count}/${maxRequests} in window, ` +
        `retry after ${retryAfterSeconds}s): ${req.method} ${req.path}`,
      );

      res.status(429).json({
        status: 'error',
        message,
        retry_after_seconds: retryAfterSeconds,
      });
      return;
    }

    next();
  };
}

// ── Pre-configured limiters for auth routes ───────────────────────────
//
// These are the recommended rate limits for Phase 1 auth endpoints.
// Each returns a fresh middleware instance with its own counter store.

/**
 * Rate limiter for POST /api/v1/auth/apple.
 * 10 requests per 15 minutes per IP.
 *
 * Bootstrap sign-in is infrequent (once per device install or re-auth).
 * A burst of 10 handles retries and multi-device scenarios.
 */
export function authAppleLimiter() {
  return createRateLimiter({
    windowMs: 15 * 60 * 1000,
    maxRequests: 10,
    message: 'Too many sign-in attempts. Please try again later.',
  });
}

/**
 * Rate limiter for POST /api/v1/auth/refresh.
 * 20 requests per minute per IP.
 *
 * Refresh happens every 15 min per device. 20/min handles a user with
 * multiple devices refreshing simultaneously.
 */
export function authRefreshLimiter() {
  return createRateLimiter({
    windowMs: 60 * 1000,
    maxRequests: 20,
    message: 'Too many refresh attempts. Please try again later.',
  });
}

/**
 * Rate limiter for POST /api/v1/auth/revoke.
 * 10 requests per minute per IP.
 *
 * Logout is infrequent. 10/min handles edge cases (retry logic).
 */
export function authRevokeLimiter() {
  return createRateLimiter({
    windowMs: 60 * 1000,
    maxRequests: 10,
    message: 'Too many revocation attempts. Please try again later.',
  });
}
