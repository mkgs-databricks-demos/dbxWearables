// Load Test Routes — Synthetic Data Generation & Ingestion at Scale
//
// POST /api/v1/testing/load-test
//   Generates synthetic HealthKit payloads and ingests them directly
//   through the ZeroBus gRPC stream pool (bypasses HTTP ingest route).
//   Returns throughput metrics for benchmarking.
//
// Two execution modes:
//   POST /api/v1/testing/load-test         — single-shot (returns JSON)
//   POST /api/v1/testing/load-test/stream   — SSE streaming (emits
//     progress events after each batch for real-time UI updates)

import express from 'express';
import type { Application, Request, Response } from 'express';
import { syntheticDataService } from '../../services/synthetic-data-service.js';
import { type RecordType, RECORD_TYPES } from '../../../shared/synthetic-healthkit.js';

// ── AppKit interface ──────────────────────────────────────────────────

interface AppKitServer {
  server: {
    extend(fn: (app: Application) => void): void;
  };
}

// ── Request / response types ──────────────────────────────────────────

interface LoadTestRequest {
  /** Number of payloads per record type. Each payload = 1-3 records. */
  counts: Partial<Record<RecordType, number>>;
  /** Max records per ingestRecords() call (default: 500) */
  batchSize?: number;
  /** User ID stamped on records (default: 'synthetic-load-test') */
  userId?: string;
  /** Source platform stamped on records (default: 'synthetic') */
  sourcePlatform?: string;
}

// ── Route registration ────────────────────────────────────────────────

export async function setupLoadTestRoutes(appkit: AppKitServer) {
  console.log('[LoadTest] Registering synthetic data load test routes');

  appkit.server.extend((app) => {
    // Parse JSON bodies for the testing endpoints
    const jsonParser = express.json({ limit: '1mb' });

    // ── POST /api/v1/testing/load-test ─────────────────────────────
    //
    // Generates synthetic payloads and ingests directly via ZeroBus SDK.
    // Client sends chunked requests for progress; each returns metrics.

    app.post(
      '/api/v1/testing/load-test',
      jsonParser,
      async (req: Request, res: Response) => {
        try {
          const body = req.body as LoadTestRequest;

          if (!body.counts || typeof body.counts !== 'object') {
            res.status(400).json({
              status: 'error',
              message: 'Missing "counts" object. Provide { counts: { samples: N, workouts: N, ... } }',
            });
            return;
          }

          // Validate record types
          const invalidTypes = Object.keys(body.counts).filter(
            (k) => !RECORD_TYPES.includes(k as RecordType),
          );
          if (invalidTypes.length > 0) {
            res.status(400).json({
              status: 'error',
              message: `Unknown record types: ${invalidTypes.join(', ')}. Valid: ${RECORD_TYPES.join(', ')}`,
            });
            return;
          }

          const totalPayloads = Object.values(body.counts).reduce(
            (sum, n) => sum + (n ?? 0),
            0,
          );

          console.log(
            `[LoadTest] Starting: ${totalPayloads} payloads across ${Object.keys(body.counts).length} type(s)`,
          );

          const result = await syntheticDataService.generateAndIngest(
            body.counts as Partial<Record<RecordType, number>>,
            {
              batchSize: body.batchSize ?? 500,
              userId: body.userId ?? 'synthetic-load-test',
              sourcePlatform: body.sourcePlatform ?? 'synthetic',
            },
          );

          console.log(
            `[LoadTest] Complete: ${result.totalRecords} records in ${result.totalDurationMs}ms (${result.recordsPerSec} rec/s)`,
          );

          res.json({
            status: 'success',
            ...result,
          });
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[LoadTest] Failed:', message);
          res.status(500).json({
            status: 'error',
            message: `Load test failed: ${message}`,
          });
        }
      },
    );


    // ── POST /api/v1/testing/load-test/stream (SSE) ────────────────
    //
    // Same inputs as /load-test, but returns a text/event-stream.
    // The server processes all batches in a single request and emits:
    //   event: progress — after each batch (cumulative metrics)
    //   event: complete — when all batches finish
    //   event: error    — if ingestion fails
    //
    // Client reads via fetch() + ReadableStream (not EventSource, since
    // this is a POST with a JSON body). Client abort = reader.cancel()
    // which closes the connection and triggers req 'close' on the server.

    app.post(
      '/api/v1/testing/load-test/stream',
      jsonParser,
      async (req: Request, res: Response) => {
        try {
          const body = req.body as LoadTestRequest;

          if (!body.counts || typeof body.counts !== 'object') {
            res.status(400).json({
              status: 'error',
              message: 'Missing "counts" object. Provide { counts: { samples: N, workouts: N, ... } }',
            });
            return;
          }

          // Validate record types
          const invalidTypes = Object.keys(body.counts).filter(
            (k) => !RECORD_TYPES.includes(k as RecordType),
          );
          if (invalidTypes.length > 0) {
            res.status(400).json({
              status: 'error',
              message: `Unknown record types: ${invalidTypes.join(', ')}. Valid: ${RECORD_TYPES.join(', ')}`,
            });
            return;
          }

          const totalPayloads = Object.values(body.counts).reduce(
            (sum, n) => sum + (n ?? 0),
            0,
          );

          console.log(
            `[LoadTest/SSE] Starting: ${totalPayloads} payloads across ${Object.keys(body.counts).length} type(s)`,
          );

          // ── Set SSE headers ─────────────────────────────────────
          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'X-Accel-Buffering': 'no', // Disable nginx/proxy buffering
          });

          // Force headers to the client immediately so the browser
          // enters streaming mode (starts reading response.body).
          res.flushHeaders();

          // ── Abort detection ─────────────────────────────────────
          // When the client calls reader.cancel() or abortController.abort(),
          // the TCP connection closes and Express fires req 'close'.
          const abortController = new AbortController();
          let clientDisconnected = false;
          req.on('close', () => {
            clientDisconnected = true;
            abortController.abort();
            console.log('[LoadTest/SSE] Client disconnected — aborting');
          });

          // Helper: write an SSE event and flush immediately.
          // Without flush(), Express compression middleware (or Node.js
          // internal buffering) holds data in memory instead of pushing
          // it to the socket — the client never sees progress events.
          const writeEvent = (event: string, data: unknown) => {
            if (!clientDisconnected) {
              res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
              // Flush through compression middleware if present.
              // The `compression` npm package patches res to add flush().
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              if (typeof (res as any).flush === 'function') (res as any).flush();
            }
          };

          const result = await syntheticDataService.generateAndIngestStreaming(
            body.counts as Partial<Record<RecordType, number>>,
            {
              batchSize: body.batchSize ?? 500,
              userId: body.userId ?? 'synthetic-load-test',
              sourcePlatform: body.sourcePlatform ?? 'synthetic',
              signal: abortController.signal,
              onProgress: (event) => writeEvent('progress', event),
            },
          );

          console.log(
            `[LoadTest/SSE] Complete: ${result.totalRecords} records in ${result.totalDurationMs}ms (${result.recordsPerSec} rec/s)`,
          );

          writeEvent('complete', { status: 'success', ...result });
          if (!clientDisconnected) res.end();
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[LoadTest/SSE] Failed:', message);

          // Try to send error event (client may already be disconnected)
          try {
            res.write(`event: error\ndata: ${JSON.stringify({ status: 'error', message })}\n\n`);
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            if (typeof (res as any).flush === 'function') (res as any).flush();
            res.end();
          } catch {
            // Client already gone — nothing to do
          }
        }
      },
    );

    // ── GET /api/v1/testing/health ──────────────────────────────────
    // Quick check that the testing routes are registered

    app.get('/api/v1/testing/health', (_req: Request, res: Response) => {
      res.json({ status: 'ok', service: 'synthetic-load-test' });
    });
  });
}
