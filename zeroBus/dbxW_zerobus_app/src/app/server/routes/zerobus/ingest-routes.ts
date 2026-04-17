// ZeroBus HealthKit Ingest Routes
//
// POST /api/v1/healthkit/ingest — receives NDJSON payloads from the iOS
//   HealthKit demo app and streams each line to the wearables_zerobus
//   bronze table via the ZeroBus TypeScript SDK.
//
// GET  /api/v1/healthkit/health — lightweight health/readiness check.
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
import type { Application, Request, Response } from 'express';
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

// ── NDJSON body parser ───────────────────────────────────────────────────
// Parses the raw request body as UTF-8 text for NDJSON content types.
// 10 MB limit aligns with ZeroBus per-record maximum.

const ndjsonParser = express.text({
  type: ['application/x-ndjson', 'application/ndjson', 'text/plain'],
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
    // ── POST /api/v1/healthkit/ingest ────────────────────────────────
    //
    // 1. Validate X-Record-Type header
    // 2. Parse NDJSON body into individual JSON objects
    // 3. Build WearablesRecord per line (UUID, timestamp, VARIANT columns)
    // 4. Batch-ingest via ZeroBus SDK
    // 5. Block until all records are durable in the bronze table
    // 6. Return success response with record IDs

    app.post(
      '/api/v1/healthkit/ingest',
      ndjsonParser,
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

          // — Parse NDJSON body ─────────────────────────────────────────
          const rawBody = typeof req.body === 'string' ? req.body : '';

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

          // — Ingest via ZeroBus SDK (blocks until durable) ─────────────
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
