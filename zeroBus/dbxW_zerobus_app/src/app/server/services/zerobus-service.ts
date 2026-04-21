// ZeroBus Ingest Service — Singleton (SDK Streaming)
//
// Ingests records into the wearables_zerobus bronze table via the ZeroBus
// TypeScript SDK (@databricks/zerobus-ingest-sdk). Uses persistent gRPC
// streams with a configurable pool for enterprise-scale throughput.
//
// The SDK wraps the high-performance Rust core via NAPI-RS native bindings,
// providing native performance with Rust async I/O mapped to JavaScript
// Promises. OAuth M2M authentication is handled internally by the SDK —
// no manual token management required.
//
// Scaling strategy: open more streams. Each stream is a direct gRPC
// connection to the ZeroBus Ingest server with per-stream ordering
// guarantees. The pool round-robins requests across streams for
// parallelism. Cross-stream ordering is NOT guaranteed (acceptable:
// each iOS POST is independent).
//
// Environment variables (injected via app.yaml valueFrom directives):
//   ZEROBUS_ENDPOINT          — ZeroBus Ingest server endpoint
//   ZEROBUS_WORKSPACE_URL     — Databricks workspace URL
//   ZEROBUS_TARGET_TABLE      — Fully qualified bronze table name
//   ZEROBUS_CLIENT_ID         — ZeroBus SPN application_id (OAuth M2M)
//   ZEROBUS_CLIENT_SECRET     — ZeroBus SPN OAuth secret
//   ZEROBUS_STREAM_POOL_SIZE  — (optional) Number of concurrent gRPC streams (default: 4)
//
// Table schema (hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus):
//   record_id       STRING  NOT NULL  — Server-generated GUID (PK)
//   ingested_at     TIMESTAMP         — Epoch microseconds
//   body            VARIANT           — Raw NDJSON line as JSON-encoded string
//   headers         VARIANT           — HTTP request headers as JSON-encoded string
//   record_type     STRING            — From X-Record-Type header
//   source_platform STRING            — From X-Platform header (e.g. "apple_healthkit")
//   user_id         STRING            — App-authenticated user ID from JWT claims
//
// SDK reference:
//   https://github.com/databricks/zerobus-sdk/tree/main/typescript
//   https://docs.databricks.com/aws/en/ingestion/zerobus-ingest/

import crypto from 'node:crypto';
import { ZerobusSdk, RecordType } from '@databricks/zerobus-ingest-sdk';

// ── Types matching the bronze table schema ───────────────────────────────

export interface WearablesRecord {
  record_id: string;       // NOT NULL PK — crypto.randomUUID()
  ingested_at: number;     // TIMESTAMP   — epoch microseconds (Date.now() * 1000)
  body: string;            // VARIANT     — JSON.stringify(parsedNdjsonLine)
  headers: string;         // VARIANT     — JSON.stringify(httpHeaders)
  record_type: string;     // STRING      — e.g. "samples", "workouts", "sleep"
  source_platform: string; // STRING      — e.g. "apple_healthkit", "android_health_connect"
  user_id: string;         // STRING      — app-authenticated user ID (default 'anonymous')
}

// ── Required env var names ───────────────────────────────────────────────

const ENV_KEYS = [
  'ZEROBUS_ENDPOINT',
  'ZEROBUS_WORKSPACE_URL',
  'ZEROBUS_TARGET_TABLE',
  'ZEROBUS_CLIENT_ID',
  'ZEROBUS_CLIENT_SECRET',
] as const;

// ── Stream pool defaults ─────────────────────────────────────────────────

const DEFAULT_POOL_SIZE = 4;

// ── SDK stream interface ─────────────────────────────────────────────────
//
// Minimal interface matching the stream returned by ZerobusSdk.createStream().
// Using an explicit interface rather than type inference avoids coupling to
// the SDK's internal NAPI-RS type definitions.

interface IngestStream {
  ingestRecordOffset(record: unknown): Promise<bigint>;
  waitForOffset(offset: bigint): Promise<void>;
  close(): Promise<void>;
}

// ── Service class ────────────────────────────────────────────────────────

class ZeroBusService {
  private sdk: ZerobusSdk | null = null;
  private streams: IngestStream[] = [];
  private streamIndex = 0;
  private poolSize: number;
  private initPromise: Promise<void> | null = null;

  constructor(poolSize?: number) {
    this.poolSize = poolSize ??
      parseInt(process.env.ZEROBUS_STREAM_POOL_SIZE || '', 10) ||
      DEFAULT_POOL_SIZE;
  }

  // ── Stream pool management ─────────────────────────────────────────

  /**
   * Lazily initialize the SDK and open a pool of gRPC streams.
   *
   * Called on the first ingest request. Concurrent callers await the
   * same promise — only one initialization runs at a time.
   *
   * Each stream is an independent gRPC connection to the ZeroBus server.
   * The SDK handles OAuth M2M token acquisition and refresh internally
   * via the client_id / client_secret credentials.
   */
  private async ensurePool(): Promise<void> {
    if (this.streams.length > 0) return;

    // Prevent concurrent initialization — all callers await the same promise
    if (this.initPromise) {
      await this.initPromise;
      return;
    }

    this.initPromise = this.initializePool();
    try {
      await this.initPromise;
    } finally {
      this.initPromise = null;
    }
  }

  private async initializePool(): Promise<void> {
    const endpoint = process.env.ZEROBUS_ENDPOINT!;
    const workspaceUrl = process.env.ZEROBUS_WORKSPACE_URL!;
    const targetTable = process.env.ZEROBUS_TARGET_TABLE!;
    const clientId = process.env.ZEROBUS_CLIENT_ID!;
    const clientSecret = process.env.ZEROBUS_CLIENT_SECRET!;

    console.log(
      `[ZeroBus] Initializing SDK stream pool (size: ${this.poolSize}, table: ${targetTable})`,
    );

    this.sdk = new ZerobusSdk(endpoint, workspaceUrl);

    // Open all streams in parallel for faster startup
    const streamPromises = Array.from({ length: this.poolSize }, (_, i) =>
      this.sdk!.createStream(
        { tableName: targetTable },
        clientId,
        clientSecret,
        { recordType: RecordType.Json },
      ).then((stream: IngestStream) => {
        console.log(`[ZeroBus] Stream ${i + 1}/${this.poolSize} opened`);
        return stream;
      }),
    );

    this.streams = await Promise.all(streamPromises);
    console.log(`[ZeroBus] Stream pool ready (${this.streams.length} streams)`);
  }

  /**
   * Round-robin stream selection.
   *
   * Each Express request gets the next stream in the pool. Cross-stream
   * ordering is NOT guaranteed — acceptable because each iOS POST is an
   * independent batch from a different user/sync session.
   */
  private nextStream(): IngestStream {
    const stream = this.streams[this.streamIndex];
    this.streamIndex = (this.streamIndex + 1) % this.streams.length;
    return stream;
  }

  // ── Record builder ───────────────────────────────────────────────────

  /**
   * Build a WearablesRecord for one NDJSON line.
   *
   * VARIANT columns (body, headers) are stored as JSON-encoded strings per
   * ZeroBus Ingest requirements:
   *   https://docs.databricks.com/aws/en/ingestion/zerobus-limits/
   *
   * TIMESTAMP is epoch microseconds (int64).
   */
  buildRecord(
    body: unknown,
    headers: Record<string, string>,
    recordType: string,
    sourcePlatform: string,
    userId: string = 'anonymous',
  ): WearablesRecord {
    return {
      record_id: crypto.randomUUID(),
      ingested_at: Date.now() * 1000, // ms → μs
      body: JSON.stringify(body), // VARIANT — JSON-encoded string
      headers: JSON.stringify(headers), // VARIANT — JSON-encoded string
      record_type: recordType,
      source_platform: sourcePlatform,
      user_id: userId,
    };
  }

  // ── Batch ingest via SDK stream ──────────────────────────────────────

  /**
   * Ingest an array of pre-built records via the ZeroBus SDK stream pool.
   *
   * Each record is written to a gRPC stream via ingestRecordOffset(),
   * which queues the record for sending and returns a monotonic offset.
   * After all records are written, waitForOffset() blocks until the last
   * record is durably committed to the Delta table.
   *
   * The SDK's Rust async runtime handles network I/O, batching, and
   * OAuth token lifecycle — the Node.js event loop is not blocked.
   *
   * @returns The number of records durably ingested.
   */
  async ingestRecords(records: WearablesRecord[]): Promise<number> {
    if (records.length === 0) return 0;

    // Validate env vars before attempting ingestion
    const envCheck = this.checkEnv();
    if (!envCheck.configured) {
      throw new Error(
        `Missing required ZeroBus env vars: ${envCheck.missing.join(', ')}`,
      );
    }

    await this.ensurePool();
    const stream = this.nextStream();

    // Write all records to the stream — ingestRecordOffset() queues each
    // record and returns quickly. The Rust runtime sends them efficiently
    // over the gRPC connection. We only need the last offset for the
    // durability check.
    let lastOffset = BigInt(0);
    for (const record of records) {
      lastOffset = await stream.ingestRecordOffset(record);
    }

    // Block until the last record is durably committed to the Delta table.
    // All preceding records (with lower offsets) are guaranteed durable
    // once this returns.
    await stream.waitForOffset(lastOffset);

    return records.length;
  }

  // ── Health check ─────────────────────────────────────────────────────

  /** Check whether all required env vars are present. */
  checkEnv(): { configured: boolean; missing: string[] } {
    const missing = ENV_KEYS.filter((k) => !process.env[k]);
    return { configured: missing.length === 0, missing: [...missing] };
  }

  /** Stream pool status for the health check endpoint. */
  poolStatus(): { pool_size: number; active_streams: number; initialized: boolean } {
    return {
      pool_size: this.poolSize,
      active_streams: this.streams.length,
      initialized: this.streams.length > 0,
    };
  }

  // ── Graceful shutdown ────────────────────────────────────────────────

  /**
   * Close all streams and release SDK resources.
   *
   * Called on SIGTERM for graceful shutdown. Each stream.close() flushes
   * pending records and waits for final acknowledgments before closing
   * the gRPC connection.
   */
  async close(): Promise<void> {
    if (this.streams.length > 0) {
      console.log(`[ZeroBus] Closing ${this.streams.length} stream(s)...`);
      await Promise.allSettled(this.streams.map((s) => s.close()));
      console.log('[ZeroBus] All streams closed');
    }
    this.streams = [];
    this.streamIndex = 0;
    this.sdk = null;
  }
}

// ── Singleton export ─────────────────────────────────────────────────────

/** Shared instance — used by all Express route handlers. */
export const zeroBusService = new ZeroBusService();
