// Timeout Utility — Promise-based timeout wrapper
//
// Provides a generic `withTimeout()` helper that races a promise against
// a timer. If the promise doesn't resolve within the deadline, a
// `TimeoutError` is thrown with a descriptive label and the configured
// duration.
//
// Used by auth-service.ts to enforce deadlines on:
//   - Apple JWKS fetch + JWT verification (10s)
//   - Individual Lakebase queries (5s)
//
// The route handlers in auth-routes.ts catch `TimeoutError` and map it
// to HTTP 504 Gateway Timeout with code `TIMEOUT`.
//
// Design notes:
//   - Uses Promise.race (not AbortSignal) for compatibility with any
//     promise-returning API, including jose and pg.
//   - The underlying operation is NOT cancelled — it continues running
//     in the background. For Lakebase queries this is acceptable since
//     Postgres will still complete the query; we just stop waiting.
//   - The timer is cleaned up on normal resolution to avoid dangling
//     handles that prevent clean process shutdown.

// ── TimeoutError ──────────────────────────────────────────────────────

/**
 * Thrown when a promise exceeds its deadline.
 *
 * Properties:
 *   - `label`:     Human-readable description of what timed out
 *   - `timeoutMs`: The configured deadline in milliseconds
 *
 * Route handlers detect this via `instanceof TimeoutError` and return
 * HTTP 504 with error code `TIMEOUT`.
 */
export class TimeoutError extends Error {
  constructor(
    public readonly label: string,
    public readonly timeoutMs: number,
  ) {
    super(`${label} timed out after ${timeoutMs}ms`);
    this.name = 'TimeoutError';
  }
}

// ── withTimeout ───────────────────────────────────────────────────────

/**
 * Race a promise against a deadline.
 *
 * @param promise  - The async operation to guard
 * @param ms       - Maximum time to wait (milliseconds)
 * @param label    - Descriptive label for error messages and logging
 * @returns The resolved value of `promise` if it completes in time
 * @throws {TimeoutError} if the deadline is exceeded
 *
 * @example
 * ```ts
 * const result = await withTimeout(
 *   fetch('https://appleid.apple.com/auth/keys'),
 *   5000,
 *   'Apple JWKS fetch',
 * );
 * ```
 */
export function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  label: string,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new TimeoutError(label, ms)),
      ms,
    );

    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}
