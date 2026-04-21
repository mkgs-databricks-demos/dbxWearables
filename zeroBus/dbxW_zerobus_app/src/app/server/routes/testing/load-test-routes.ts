// Load Test Routes — Synthetic Data Generation & Ingestion at Scale
//
// POST /api/v1/testing/load-test
//   Generates synthetic HealthKit payloads and ingests them directly
//   through the ZeroBus gRPC stream pool (bypasses HTTP ingest route).
//   Returns throughput metrics for benchmarking.
//
// Designed for chunked client requests: the frontend sends multiple
// smaller requests (e.g., 500 payloads each) and aggregates progress.
// This gives natural live progress without SSE complexity.

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

    // ── GET /api/v1/testing/health ──────────────────────────────────
    // Quick check that the testing routes are registered

    app.get('/api/v1/testing/health', (_req: Request, res: Response) => {
      res.json({ status: 'ok', service: 'synthetic-load-test' });
    });
  });
}
