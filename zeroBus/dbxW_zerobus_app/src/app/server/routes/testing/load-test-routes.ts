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
import { zeroBusService } from '../../services/zerobus-service.js';
import { type RecordType, RECORD_TYPES } from '../../../shared/synthetic-healthkit.js';
import { extractUser, extractClientIp } from '../../utils/extract-user.js';
import { loadTestHistoryService } from '../../services/load-test-history-service.js';

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

          // Extract real user identity server-side (not from client POST body)
          const userId = extractUser(req);

          const result = await syntheticDataService.generateAndIngest(
            body.counts as Partial<Record<RecordType, number>>,
            {
              batchSize: body.batchSize ?? 500,
              userId,
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

          // Extract real user identity & context server-side
          const userId = extractUser(req);
          const userIp = extractClientIp(req);
          const batchSize = body.batchSize ?? 500;

          // Capture pool state before test
          const poolBefore = zeroBusService.poolStatus();
          const autoScaleBefore = zeroBusService.autoScaleStatus();

          console.log(
            `[LoadTest/SSE] Starting: ${totalPayloads} payloads across ${Object.keys(body.counts).length} type(s) (user: ${userId})`,
          );

          // Create history record in Lakebase (non-fatal if it fails)
          let runId: string | null = null;
          try {
            runId = await loadTestHistoryService.createRun({
              userId,
              userIp,
              presetLabel: body.presetLabel ?? 'Custom',
              batchSize,
              totalPayloads,
              poolSizeStart: poolBefore.pool_size,
              autoScaleEnabled: autoScaleBefore.enabled,
              autoScaleMin: autoScaleBefore.config?.minSize,
              autoScaleMax: autoScaleBefore.config?.maxSize,
              configuredTypes: body.counts as Partial<Record<string, number>>,
            });
          } catch (histErr) {
            console.warn('[LoadTest/SSE] Failed to create history run:', (histErr as Error).message);
          }

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
          // IMPORTANT: We listen on `res.on('close')`, NOT `req.on('close')`.
          // `req.on('close')` fires when the POST request body is fully
          // consumed (~2ms for a small JSON body) — NOT when the client
          // disconnects. `res.on('close')` fires when the response stream
          // is terminated: either by our res.end() (normal) or by the
          // client aborting (reader.cancel() / AbortController.abort()).
          const abortController = new AbortController();
          let clientDisconnected = false;
          let responseEnded = false;

          res.on('close', () => {
            if (!responseEnded) {
              // Client closed the connection before we called res.end()
              clientDisconnected = true;
              abortController.abort();
              console.log('[LoadTest/SSE] Client disconnected — aborting');

              // Mark run as aborted in history
              if (runId) {
                loadTestHistoryService.completeRun(runId, {
                  status: 'aborted',
                  errorMessage: 'Client disconnected',
                  poolSizeEnd: zeroBusService.poolStatus().active,
                }).catch(() => {});
              }
            }
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
              batchSize,
              userId,
              sourcePlatform: body.sourcePlatform ?? 'synthetic',
              signal: abortController.signal,
              onProgress: (event) => writeEvent('progress', event),
            },
          );

          console.log(
            `[LoadTest/SSE] Complete: ${result.totalRecords} records in ${result.totalDurationMs}ms (${result.recordsPerSec} rec/s)`,
          );

          // Update history with final results (Lakehouse Sync handles UC replication)
          if (runId) {
            const poolAfter = zeroBusService.poolStatus();
            try {
              await loadTestHistoryService.completeRun(runId, {
                status: 'complete',
                totalRecords: result.totalRecords,
                recordsPerSec: result.recordsPerSec,
                durationMs: result.totalDurationMs,
                poolSizeEnd: poolAfter.active,
              });
              // Write per-type breakdown
              if (result.perType) {
                await loadTestHistoryService.upsertTypeResults(runId, result.perType);
              }
            } catch (histErr) {
              console.warn('[LoadTest/SSE] Failed to update history:', (histErr as Error).message);
            }
          }

          writeEvent('complete', { status: 'success', ...result });
          if (!clientDisconnected) {
            responseEnded = true;
            res.end();
          }
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[LoadTest/SSE] Failed:', message);

          // Try to send error event (client may already be disconnected)
          try {
            res.write(`event: error\ndata: ${JSON.stringify({ status: 'error', message })}\n\n`);
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            if (typeof (res as any).flush === 'function') (res as any).flush();
            responseEnded = true;
            res.end();
          } catch {
            // Client already gone — nothing to do
          }
        }
      },
    );


    // ── GET /api/v1/testing/pool-status ─────────────────────────────
    //
    // Returns the current stream pool configuration and state.
    // Used by the Load Test page to display live pool info.

    app.get(
      '/api/v1/testing/pool-status',
      (_req: Request, res: Response) => {
        const pool = zeroBusService.poolStatus();
        const autoScale = zeroBusService.autoScaleStatus();
        res.json({
          status: 'ok',
          ...pool,
          auto_scale_detail: {
            enabled: autoScale.enabled,
            config: autoScale.config,
            peak_inflight: autoScale.peak_inflight,
            idle_checks: autoScale.idle_checks,
          },
          history: autoScale.history,
        });
      },
    );


    // ── POST /api/v1/testing/pool-autoscale ─────────────────────────
    //
    // Enable or disable automatic stream pool scaling based on load.
    // When enabled, a background monitor checks utilization every few
    // seconds and adjusts the pool size within min/max bounds.
    //
    // Enable:  { "enabled": true, "minSize": 2, "maxSize": 16 }
    // Disable: { "enabled": false }

    app.post(
      '/api/v1/testing/pool-autoscale',
      jsonParser,
      (req: Request, res: Response) => {
        try {
          const { enabled, minSize, maxSize, cooldownMs, scaleUpStep, scaleDownStep } =
            req.body as {
              enabled?: boolean;
              minSize?: number;
              maxSize?: number;
              cooldownMs?: number;
              scaleUpStep?: number;
              scaleDownStep?: number;
            };

          if (enabled === undefined || typeof enabled !== 'boolean') {
            res.status(400).json({
              status: 'error',
              message: 'Missing or invalid "enabled" (boolean).',
            });
            return;
          }

          if (enabled) {
            const config = zeroBusService.enableAutoScale({
              ...(minSize !== undefined && { minSize }),
              ...(maxSize !== undefined && { maxSize }),
              ...(cooldownMs !== undefined && { cooldownMs }),
              ...(scaleUpStep !== undefined && { scaleUpStep }),
              ...(scaleDownStep !== undefined && { scaleDownStep }),
            });
            console.log(`[LoadTest] Auto-scale enabled: min=${config.minSize}, max=${config.maxSize}`);
            res.json({ status: 'success', auto_scale: { enabled: true, ...config } });
          } else {
            zeroBusService.disableAutoScale();
            console.log('[LoadTest] Auto-scale disabled');
            res.json({ status: 'success', auto_scale: { enabled: false } });
          }
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[LoadTest] Auto-scale config failed:', message);
          res.status(400).json({ status: 'error', message });
        }
      },
    );

    // ── POST /api/v1/testing/pool-resize ────────────────────────────
    //
    // Dynamically resize the gRPC stream pool without restarting.
    // Scale up: opens new streams (no disruption).
    // Scale down: drains in-flight, then closes excess streams.
    //
    // Request:  { "poolSize": 8 }
    // Response: { "status": "success", "oldSize": 2, "newSize": 8, "durationMs": 450 }

    app.post(
      '/api/v1/testing/pool-resize',
      jsonParser,
      async (req: Request, res: Response) => {
        try {
          const { poolSize } = req.body as { poolSize?: number };

          if (poolSize === undefined || typeof poolSize !== 'number') {
            res.status(400).json({
              status: 'error',
              message: 'Missing or invalid "poolSize" (number 1–32).',
            });
            return;
          }

          console.log(`[LoadTest] Pool resize requested: ${poolSize}`);
          const result = await zeroBusService.resize(poolSize);

          console.log(
            `[LoadTest] Pool resized: ${result.oldSize} → ${result.newSize} (${result.durationMs}ms)`,
          );

          res.json({
            status: 'success',
            ...result,
          });
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[LoadTest] Pool resize failed:', message);
          res.status(400).json({
            status: 'error',
            message,
          });
        }
      },
    );

    // ── GET /api/v1/testing/health ──────────────────────────────────
    // Quick check that the testing routes are registered

    app.get('/api/v1/testing/health', (_req: Request, res: Response) => {
      res.json({ status: 'ok', service: 'synthetic-load-test' });
    });


    // ── GET /api/v1/testing/history ──────────────────────────────────
    //
    // Returns paginated load test history from Lakebase.
    // Query params: ?limit=50&offset=0

    app.get(
      '/api/v1/testing/history',
      async (req: Request, res: Response) => {
        try {
          const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
          const offset = Math.max(parseInt(req.query.offset as string) || 0, 0);
          const runs = await loadTestHistoryService.listRuns(limit, offset);
          res.json({ status: 'ok', runs, limit, offset });
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[LoadTest/History] List failed:', message);
          res.status(500).json({ status: 'error', message });
        }
      },
    );


    // ── GET /api/v1/testing/history/:runId ───────────────────────────
    //
    // Returns a single run with per-type breakdown.

    app.get(
      '/api/v1/testing/history/:runId',
      async (req: Request, res: Response) => {
        try {
          const run = await loadTestHistoryService.getRun(req.params.runId);
          if (!run) {
            res.status(404).json({ status: 'error', message: 'Run not found' });
            return;
          }
          res.json({ status: 'ok', ...run });
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.error('[LoadTest/History] Get failed:', message);
          res.status(500).json({ status: 'error', message });
        }
      },
    );
  });
}
