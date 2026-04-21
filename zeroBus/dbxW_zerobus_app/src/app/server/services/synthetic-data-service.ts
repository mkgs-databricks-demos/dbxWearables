// Synthetic Data Service — Server-Side Bulk Generation & Ingestion
//
// Wraps the shared synthetic-healthkit generators with:
//   1. Batch generation — configurable record counts per type
//   2. Direct-to-ZeroBus ingestion — bypasses HTTP, calls zeroBusService
//      directly for maximum throughput during load testing
//   3. Throughput metrics — records/sec, duration, per-type breakdowns
//
// Usage:
//   import { syntheticDataService } from './synthetic-data-service.js';
//
//   // Generate only (returns NDJSON strings)
//   const payloads = syntheticDataService.generate({ samples: 1000, workouts: 500 });
//
//   // Generate AND ingest (bypasses HTTP — direct to gRPC stream pool)
//   const result = await syntheticDataService.generateAndIngest({ samples: 1000 });
//   console.log(result.metrics); // { totalRecords, durationMs, recordsPerSec, ... }

import {
  type RecordType,
  type GeneratedPayload,
  RECORD_TYPES,
  generatePayload,
  AVG_RECORDS_PER_PAYLOAD,
} from '../../shared/synthetic-healthkit.js';

import { zeroBusService } from './zerobus-service.js';

// ── Types ────────────────────────────────────────────────────────────────

/** Per-type record counts for batch generation */
export type RecordCounts = Partial<Record<RecordType, number>>;

/** Result of a generate-only operation */
export interface GenerateResult {
  /** Per-type payloads with NDJSON and parsed records */
  payloads: Map<RecordType, GeneratedPayload[]>;
  /** Combined NDJSON string across all types (for bulk POST) */
  combinedNdjson: string;
  /** Total number of individual records generated */
  totalRecords: number;
  /** Generation duration in milliseconds */
  durationMs: number;
}

/** Per-type ingestion breakdown */
export interface TypeMetrics {
  recordType: RecordType;
  recordCount: number;
  durationMs: number;
}

/** Result of a generate-and-ingest operation */
export interface IngestResult {
  /** Total records ingested across all types */
  totalRecords: number;
  /** Total wall-clock duration in milliseconds */
  totalDurationMs: number;
  /** Effective throughput (records / second) */
  recordsPerSec: number;
  /** Per-type breakdown */
  perType: TypeMetrics[];
}


/** Progress event emitted after each batch during streaming ingestion */
export interface ProgressEvent {
  /** Current batch index (1-based) */
  chunk: number;
  /** Estimated total batches */
  chunksTotal: number;
  /** Cumulative records ingested so far */
  totalRecords: number;
  /** Wall-clock ms since start */
  totalDurationMs: number;
  /** Current throughput (records/sec) */
  recordsPerSec: number;
  /** Per-type cumulative breakdown */
  perType: TypeMetrics[];
}

// ── Service ──────────────────────────────────────────────────────────────

class SyntheticDataService {
  /**
   * Generate synthetic payloads without ingesting.
   *
   * Returns per-type payloads and a combined NDJSON string suitable for
   * a bulk POST to the ingest endpoint (for testing via HTTP).
   *
   * @param counts - Number of payloads per record type to generate.
   *                 Each payload contains 1-3 records depending on type.
   *                 Example: { samples: 100, workouts: 50 } generates
   *                 ~300 sample records + 50 workout records.
   */
  generate(counts: RecordCounts): GenerateResult {
    const start = performance.now();
    const payloads = new Map<RecordType, GeneratedPayload[]>();
    let totalRecords = 0;
    const ndjsonParts: string[] = [];

    for (const rt of RECORD_TYPES) {
      const count = counts[rt] ?? 0;
      if (count <= 0) continue;

      const typePayloads: GeneratedPayload[] = [];
      for (let i = 0; i < count; i++) {
        const payload = generatePayload(rt);
        typePayloads.push(payload);
        totalRecords += payload.recordCount;
        ndjsonParts.push(payload.ndjson);
      }
      payloads.set(rt, typePayloads);
    }

    return {
      payloads,
      combinedNdjson: ndjsonParts.join('\n'),
      totalRecords,
      durationMs: Math.round(performance.now() - start),
    };
  }

  /**
   * Generate synthetic payloads AND ingest them directly via ZeroBus.
   *
   * Bypasses the HTTP layer entirely — generates records, wraps them in
   * WearablesRecord format (matching the bronze table schema), and feeds
   * them straight into zeroBusService.ingestRecords(). This is the
   * fastest path for at-scale load testing.
   *
   * Each batch of records for a given type is ingested as a single call
   * to zeroBusService.ingestRecords(), which writes to the gRPC stream
   * pool and waits for durability acknowledgment.
   *
   * @param counts - Number of payloads per record type to generate/ingest.
   * @param options.batchSize - Max records per ingestRecords() call (default: 500).
   *                            Larger batches = fewer round-trips but more memory.
   * @param options.userId - User ID stamped on each record (default: 'synthetic-load-test').
   * @param options.sourcePlatform - Platform stamped on each record (default: 'synthetic').
   */
  async generateAndIngest(
    counts: RecordCounts,
    options: {
      batchSize?: number;
      userId?: string;
      sourcePlatform?: string;
    } = {},
  ): Promise<IngestResult> {
    const {
      batchSize = 500,
      userId = 'synthetic-load-test',
      sourcePlatform = 'synthetic',
    } = options;

    const totalStart = performance.now();
    const perType: TypeMetrics[] = [];
    let totalRecords = 0;

    // Build synthetic headers matching what the iOS app sends
    const syntheticHeaders: Record<string, string> = {
      'content-type': 'application/x-ndjson',
      'x-platform': sourcePlatform,
      'x-app-version': 'synthetic-data-service',
      'x-device-id': 'load-test',
      'x-upload-timestamp': new Date().toISOString(),
    };

    for (const rt of RECORD_TYPES) {
      const count = counts[rt] ?? 0;
      if (count <= 0) continue;

      const typeStart = performance.now();
      let typeRecordCount = 0;

      // Generate all payloads for this type
      const allRecords = [];
      for (let i = 0; i < count; i++) {
        const payload = generatePayload(rt);
        for (const record of payload.records) {
          allRecords.push(record);
        }
      }

      // Build WearablesRecords and ingest in batches
      const headersWithType = {
        ...syntheticHeaders,
        'x-record-type': rt,
      };

      for (let offset = 0; offset < allRecords.length; offset += batchSize) {
        const batch = allRecords.slice(offset, offset + batchSize);
        const wearablesRecords = batch.map((record) =>
          zeroBusService.buildRecord(
            record,
            headersWithType,
            rt,
            sourcePlatform,
            userId,
          ),
        );
        await zeroBusService.ingestRecords(wearablesRecords);
        typeRecordCount += wearablesRecords.length;
      }

      totalRecords += typeRecordCount;
      perType.push({
        recordType: rt,
        recordCount: typeRecordCount,
        durationMs: Math.round(performance.now() - typeStart),
      });
    }

    const totalDurationMs = Math.round(performance.now() - totalStart);

    return {
      totalRecords,
      totalDurationMs,
      recordsPerSec:
        totalDurationMs > 0
          ? Math.round((totalRecords / totalDurationMs) * 1000)
          : 0,
      perType,
    };
  }


  /**
   * Streaming variant of generateAndIngest — emits progress events via
   * callback after each batch, enabling SSE streaming to the client.
   *
   * Accepts an AbortSignal for client-disconnect cancellation.
   *
   * @param counts - Number of payloads per record type to generate/ingest.
   * @param options.batchSize - Max records per ingestRecords() call.
   * @param options.userId - User ID stamped on each record.
   * @param options.sourcePlatform - Platform stamped on each record.
   * @param options.onProgress - Callback invoked after each batch with cumulative metrics.
   * @param options.signal - AbortSignal; when aborted, stops after the current batch.
   */
  async generateAndIngestStreaming(
    counts: RecordCounts,
    options: {
      batchSize?: number;
      userId?: string;
      sourcePlatform?: string;
      onProgress?: (event: ProgressEvent) => void;
      signal?: AbortSignal;
    } = {},
  ): Promise<IngestResult> {
    const {
      batchSize = 500,
      userId = 'synthetic-load-test',
      sourcePlatform = 'synthetic',
      onProgress,
      signal,
    } = options;

    const totalStart = performance.now();
    const perType: TypeMetrics[] = [];
    let totalRecords = 0;

    const syntheticHeaders: Record<string, string> = {
      'content-type': 'application/x-ndjson',
      'x-platform': sourcePlatform,
      'x-app-version': 'synthetic-data-service',
      'x-device-id': 'load-test',
      'x-upload-timestamp': new Date().toISOString(),
    };

    // Pre-estimate total batches for progress percentage
    let estimatedTotalChunks = 0;
    for (const rt of RECORD_TYPES) {
      const count = counts[rt] ?? 0;
      if (count <= 0) continue;
      const avgRecords = AVG_RECORDS_PER_PAYLOAD[rt] ?? 1;
      estimatedTotalChunks += Math.ceil((count * avgRecords) / batchSize);
    }

    let currentChunk = 0;

    for (const rt of RECORD_TYPES) {
      const count = counts[rt] ?? 0;
      if (count <= 0) continue;
      if (signal?.aborted) break;

      const typeStart = performance.now();
      let typeRecordCount = 0;

      // Generate all payloads for this type
      const allRecords: unknown[] = [];
      for (let i = 0; i < count; i++) {
        const payload = generatePayload(rt);
        for (const record of payload.records) {
          allRecords.push(record);
        }
      }

      const headersWithType = { ...syntheticHeaders, 'x-record-type': rt };

      for (let offset = 0; offset < allRecords.length; offset += batchSize) {
        if (signal?.aborted) break;

        const batch = allRecords.slice(offset, offset + batchSize);
        const wearablesRecords = batch.map((record) =>
          zeroBusService.buildRecord(record, headersWithType, rt, sourcePlatform, userId),
        );
        await zeroBusService.ingestRecords(wearablesRecords);
        typeRecordCount += wearablesRecords.length;
        totalRecords += wearablesRecords.length;
        currentChunk++;

        // Update per-type metrics
        const typeDurationMs = Math.round(performance.now() - typeStart);
        const idx = perType.findIndex((p) => p.recordType === rt);
        const typeEntry = { recordType: rt, recordCount: typeRecordCount, durationMs: typeDurationMs };
        if (idx >= 0) perType[idx] = typeEntry;
        else perType.push(typeEntry);

        const totalDurationMs = Math.round(performance.now() - totalStart);

        onProgress?.({
          chunk: currentChunk,
          chunksTotal: estimatedTotalChunks,
          totalRecords,
          totalDurationMs,
          recordsPerSec: totalDurationMs > 0 ? Math.round((totalRecords / totalDurationMs) * 1000) : 0,
          perType: [...perType],
        });
      }
    }

    const totalDurationMs = Math.round(performance.now() - totalStart);

    return {
      totalRecords,
      totalDurationMs,
      recordsPerSec: totalDurationMs > 0 ? Math.round((totalRecords / totalDurationMs) * 1000) : 0,
      perType,
    };
  }

  /** Convenience: generate one payload of each type (for health check / smoke test) */
  generateSmoke(): GenerateResult {
    const counts: RecordCounts = {};
    for (const rt of RECORD_TYPES) {
      counts[rt] = 1;
    }
    return this.generate(counts);
  }
}

// ── Singleton export ─────────────────────────────────────────────────────

export const syntheticDataService = new SyntheticDataService();

// Re-export shared types for convenience
export { type RecordType, type GeneratedPayload, RECORD_TYPES };
export type { ProgressEvent };
