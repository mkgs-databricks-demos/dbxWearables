// ZeroBus HealthKit Ingest Routes
//
// POST /api/v1/healthkit/ingest — receives NDJSON payloads from the iOS
//   HealthKit demo app and streams each line to the wearables_zerobus
//   bronze table via the ZeroBus REST API.
//
// GET  /api/v1/healthkit/health — lightweight health/readiness check.
//
// ── Content-Type handling ────────────────────────────────────────────────
//
// AppKit's server plugin registers a global express.json() middleware that
// processes requests before route-level middleware. This creates two issues
// for NDJSON payloads sent with Content-Type: application/x-ndjson:
//
//   1. Multi-line NDJSON (not valid JSON): express.json() rejects with 400
//   2. Single-line NDJSON (valid JSON): express.json() parses it into an
//      object, and our route handler sees an object instead of a string.
//
// Fix:
//   - An error-recovery middleware catches JSON parse failures for NDJSON
//     content types and recovers the raw body string from err.body.
//   - extractNdjsonBody() handles all body states: string (from
//     express.text()), object (from express.json()), Buffer, or undefined.
//
// Supported Content-Types:
//   - application/x-ndjson  (standard NDJSON, used by iOS app)
//   - application/ndjson    (alternative NDJSON MIME type)
//   - text/plain            (fallback, bypasses JSON parser entirely)
//
// Request contract (iOS app → this endpoint):
//   Content-Type: application/x-ndjson
//   X-Record-Type: samples | workouts | sleep | activity_summaries | deletes
//   Body: one JSON object per line (NDJSON)
//
// Response contract (this endpoint → iOS app):
//   { status: "success"|"error", message: string, record_id?: string,
//     records_ingested?: number, record_ids?: string[], duration_ms?: number }
//   (compatible with healthKit/Models/APIResponse.swift — unknown keys ignored)

import express from 'express';
import type { Application, Request, Response, NextFunction } from 'express';
import { zeroBusService } from '../../services/zerobus-service';
import type { WearablesRecord } from '../../services/zerobus-service';

// ── Valid X-Record-Type values (matches iOS record type enum) ────────────

const VALID_RECORD_TYPES = new Set([
  'samples',
  'workouts',
  'sleep',
  'activity_summaries',
  'deletes',
]);

// ── Text body parser (fallback for text/plain requests) ──────────────────
// Only handles text/plain; NDJSON content types are handled by the error
// recovery middleware + extractNdjsonBody() below.

const textParser = express.text({
  type: ['text/plain'],
  limit: '10mb',
});

// ── Helpers ──────────────────────────────────────────────────────────────

/** Headers worth preserving alongside each record for debugging/audit. */
const HEADERS_TO_KEEP = [
  'x-record-type',
  'x-device-id',
  'x-sync-session-id',
  'x-batch-index',
  'x-batch-count',
  'content-type',
  'user-agent',
];

/** Extract a sanitized subset of HTTP headers for VARIANT storage. */
function extractHeaders(req: Request): Record<string, string> {
  const headers: Record<string, string> = {};
  for (const key of HEADERS_TO_KEEP) {
    const value = req.headers[key];
    if (typeof value === 'string') headers[key] = value;
  }
  return headers;
}

/** Parse an NDJSON string into valid objects and per-line errors. */
function parseNdjson(raw: string): { lines: unknown[]; errors: string[] } {
  const lines: unknown[] = [];
  const errors: string[] = [];
  const rawLines = raw.split(/\r?\n/).filter((l) => l.trim().length > 0);

  for (let i = 0; i < rawLines.length; i++) {
    try {
      lines.push(JSON.parse(rawLines[i]));
    } catch {
      errors.push(`Line ${i + 1}: invalid JSON`);
    }
  }
  return { lines, errors };
}

/**
 * Extract the NDJSON body string from the request, handling all possible
 * body states after Express middleware processing:
 *
 *   - string:    express.text() parsed it, or error recovery set it
 *   - Buffer:    express.raw() parsed it
 *   - object:    express.json() parsed single-line NDJSON (valid JSON)
 *   - undefined: no parser matched
 */
function extractNdjsonBody(req: Request): string {
  if (typeof req.body === 'string') {
    return req.body;
  }
  if (Buffer.isBuffer(req.body)) {
    return req.body.toString('utf-8');
  }
  if (
    req.body !== undefined &&
    req.body !== null &&
    typeof req.body === 'object'
  ) {
    // express.json() successfully parsed a single NDJSON line.
    // Re-serialize back to a single-line NDJSON string.
    return JSON.stringify(req.body);
  }
  return '';
}

// ── AppKit interface (only the server plugin is needed) ──────────────────

interface AppKitServer {
  server: {
    extend(fn: (app: Application) => void): void;
  };
}

// ── Route registration ───────────────────────────────────────────────────

export async function setupZeroBusRoutes(appkit: AppKitServer) {
  // Pre-flight: check env vars at startup (stream created lazily on first request)
  const envCheck = zeroBusService.checkEnv();
  if (!envCheck.configured) {
    console.warn(
      `[ZeroBus] Missing env vars (stream will fail on first request): ${envCheck.missing.join(', ')}`,
    );
  } else {
    console.log(
      '[ZeroBus] All env vars present — stream will initialize on first ingest request',
    );
  }

  appkit.server.extend((app) => {
    // ── Error recovery for NDJSON content types ────────────────────────
    //
    // AppKit's global express.json() middleware rejects multi-line NDJSON
    // (not valid JSON) with a 400 parse error. This error-handling
    // middleware catches those failures, recovers the raw body string
    // from the error object (body-parser stores it as err.body), and
    // continues to the route handler.
    //
    // Express traverses the middleware stack for error handlers when
    // next(err) is called. This handler must be registered BEFORE the
    // route handler so Express finds it during error traversal.
    //
    // Flow (multi-line NDJSON with Content-Type: application/x-ndjson):
    //   1. express.json() tries to parse → fails → next(err)
    //   2. This error handler catches it → recovers err.body → next()
    //   3. Route handler runs with req.body = raw NDJSON string

    app.use(
      '/api/v1/healthkit/ingest',
      (
        err: Error & { type?: string; body?: string; status?: number },
        req: Request,
        res: Response,
        next: NextFunction,
      ) => {
        const contentType = (req.headers['content-type'] || '').toLowerCase();
        const isNdjsonType =
          contentType.includes('ndjson') || contentType.includes('text/plain');

        if (err.type === 'entity.parse.failed' && isNdjsonType && err.body) {
          // Recover the raw body from the failed JSON parse attempt.
          // body-parser stores the raw string as err.body when parsing fails.
          console.log(
            `[ZeroBus] Recovered NDJSON body from JSON parse error (${err.body.length} bytes)`,
          );
          req.body = err.body;
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (req as any)._body = true; // Tell downstream body parsers to skip
          return next(); // Continue WITHOUT error → route handler runs
        }

        // Not a recoverable NDJSON parse failure — pass the error along
        return next(err);
      },
    );

    // ── POST /api/v1/healthkit/ingest ────────────────────────────────
    //
    // 1. Validate X-Record-Type header
    // 2. Extract NDJSON body (handles string, object, Buffer states)
    // 3. Parse NDJSON into individual JSON objects
    // 4. Build WearablesRecord per line (UUID, timestamp, VARIANT columns)
    // 5. Batch-ingest via ZeroBus REST API
    // 6. Return success response with record IDs

    app.post(
      '/api/v1/healthkit/ingest',
      textParser,
      async (req: Request, res: Response) => {
        const startMs = Date.now();

        try {
          // — Validate X-Record-Type header ─────────────────────────────
          const recordType = (
            req.headers['x-record-type'] as string | undefined
          )?.toLowerCase();

          if (!recordType || !VALID_RECORD_TYPES.has(recordType)) {
            res.status(400).json({
              status: 'error',
              message: `Missing or invalid X-Record-Type header. Expected one of: ${[...VALID_RECORD_TYPES].join(', ')}`,
            });
            return;
          }

          // — Extract NDJSON body (handles all middleware states) ────────
          const rawBody = extractNdjsonBody(req);

          if (!rawBody) {
            res.status(400).json({
              status: 'error',
              message:
                'Request body is empty. Expected NDJSON (one JSON object per line).',
            });
            return;
          }

          const { lines, errors } = parseNdjson(rawBody);

          if (lines.length === 0) {
            res.status(400).json({
              status: 'error',
              message:
                errors.length > 0
                  ? `No valid records found. Parse errors: ${errors.join('; ')}`
                  : 'No valid records found in request body.',
            });
            return;
          }

          // — Build records matching the bronze table schema ────────────
          const headers = extractHeaders(req);
          const records: WearablesRecord[] = lines.map((line) =>
            zeroBusService.buildRecord(line, headers, recordType),
          );

          // — Ingest via ZeroBus REST API ───────────────────────────────
          const ingested = await zeroBusService.ingestRecords(records);

          const durationMs = Date.now() - startMs;
          console.log(
            `[ZeroBus] Ingested ${ingested} ${recordType} record(s) in ${durationMs}ms`,
          );

          // — Success response ──────────────────────────────────────────
          // Compatible with iOS APIResponse.swift (unknown keys ignored
          // by Swift's Codable decoder). Single-record requests get a
          // top-level record_id for backwards compatibility.
          res.status(200).json({
            status: 'success',
            message: `${ingested} record(s) ingested`,
            ...(records.length === 1 && { record_id: records[0].record_id }),
            records_ingested: ingested,
            record_ids: records.map((r) => r.record_id),
            duration_ms: durationMs,
            ...(errors.length > 0 && { parse_warnings: errors }),
          });
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[ZeroBus] Ingest failed:', message);

          res.status(500).json({
            status: 'error',
            message: `Ingestion failed: ${message}`,
          });
        }
      },
    );

    // ── GET /api/v1/healthkit/health ──────────────────────────────────

    app.get('/api/v1/healthkit/health', (_req: Request, res: Response) => {
      const envCheck = zeroBusService.checkEnv();

      res.json({
        status: 'ok',
        service: 'zerobus-healthkit-ingest',
        env_configured: envCheck.configured,
        target_table: process.env.ZEROBUS_TARGET_TABLE ?? '(not set)',
        ...(envCheck.missing.length > 0 && {
          missing_env_vars: envCheck.missing,
        }),
      });
    });
  });

  // ── Graceful shutdown ────────────────────────────────────────────────
  process.on('SIGTERM', async () => {
    console.log('[ZeroBus] SIGTERM received — closing stream');
    await zeroBusService.close();
  });
}
