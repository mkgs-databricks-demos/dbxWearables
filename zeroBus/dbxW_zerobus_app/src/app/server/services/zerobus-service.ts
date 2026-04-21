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
// Graceful shutdown:
//   On SIGTERM the service enters drain mode:
//     1. draining=true — new ingestRecords() calls are rejected immediately
//     2. In-flight requests are given up to DRAIN_TIMEOUT_MS to complete
//     3. stream.close() flushes all SDK-queued records and waits for acks
//   This guarantees every record received before SIGTERM is durably
//   committed to the Delta table, even during a redeploy.
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

// ── Drain / shutdown constants ───────────────────────────────────────────

/** Maximum time (ms) to wait for in-flight requests during graceful shutdown. */
const DRAIN_TIMEOUT_MS = 30_000;

/** Polling interval (ms) when waiting for in-flight requests to complete. */
const DRAIN_POLL_INTERVAL_MS = 250;


// ── Auto-scale configuration ─────────────────────────────────────────

/** Configuration for automatic stream pool scaling based on load. */
export interface AutoScaleConfig {
  /** Minimum pool size (default: 2). */
  minSize: number;
  /** Maximum pool size (default: 16). */
  maxSize: number;
  /** How often to check utilization, in ms (default: 3000). */
  checkIntervalMs: number;
  /** Minimum time between resize operations, in ms (default: 15000). */
  cooldownMs: number;
  /** Streams to add per scale-up event (default: 2). */
  scaleUpStep: number;
  /** Streams to remove per scale-down event (default: 1). */
  scaleDownStep: number;
}

const AUTO_SCALE_DEFAULTS: AutoScaleConfig = {
  minSize: 2,
  maxSize: 16,
  checkIntervalMs: 3_000,
  cooldownMs: 15_000,
  scaleUpStep: 2,
  scaleDownStep: 1,
};


/** Recorded each time the stream pool is resized (auto or manual). */
export interface ResizeEvent {
  /** ISO 8601 timestamp */
  timestamp: string;
  /** What triggered the resize */
  trigger: 'auto-scale-up' | 'auto-scale-down' | 'manual' | 'initial';
  /** Pool size before */
  oldSize: number;
  /** Pool size after */
  newSize: number;
  /** Duration of the resize operation in ms */
  durationMs: number;
  /** Peak in-flight at the time of the decision (auto-scale only) */
  peakInflight?: number;
  /** Consecutive idle checks at the time (auto-scale down only) */
  idleChecks?: number;
  /** ingestRecords() calls since last check (auto-scale up — call rate trigger) */
  callRate?: number;
}

/** Maximum number of resize events to retain in the ring buffer. */
const MAX_RESIZE_HISTORY = 50;

/** Number of consecutive idle checks before scaling down. */
const IDLE_CHECKS_BEFORE_SCALE_DOWN = 3;

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

  // Stored after initialization so resize() can open new streams
  // without re-reading env vars.
  private targetTable = '';
  private clientId = '';
  private clientSecret = '';

  // ── In-flight tracking for graceful shutdown ──────────────────────
  //
  // inflight counts the number of ingestRecords() calls currently
  // executing. On SIGTERM, close() sets draining=true and polls until
  // inflight reaches 0 (or DRAIN_TIMEOUT_MS elapses), then closes all
  // streams. This ensures every record received by an Express handler
  // before SIGTERM is written to a stream and flushed on close().

  private inflight = 0;
  private draining = false;

  // ── Auto-scale state ──────────────────────────────────────────
  private autoScaleEnabled = false;
  private autoScaleConfig: AutoScaleConfig = { ...AUTO_SCALE_DEFAULTS };
  private autoScaleTimer: ReturnType<typeof setInterval> | null = null;
  private lastAutoScaleTime = 0;
  private peakInflight = 0;
  private idleChecks = 0;
  private callsSinceLastCheck = 0;
  private resizeHistory: ResizeEvent[] = [];
  private _lastResizeTrigger: ResizeEvent['trigger'] | null = null;
  private _lastResizePeak?: number;
  private _lastResizeIdle?: number;
  private _lastResizeCallRate?: number;

  constructor(poolSize?: number) {
    this.poolSize = poolSize ??
      (parseInt(process.env.ZEROBUS_STREAM_POOL_SIZE || '', 10) ||
       DEFAULT_POOL_SIZE);
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

    // Store for resize() — avoid re-reading env vars
    this.targetTable = targetTable;
    this.clientId = clientId;
    this.clientSecret = clientSecret;

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
    this.recordResizeEvent({
      timestamp: new Date().toISOString(),
      trigger: 'initial',
      oldSize: 0,
      newSize: this.streams.length,
      durationMs: 0,
    });
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



  /** Record a resize event in the ring buffer. */
  private recordResizeEvent(event: ResizeEvent): void {
    this.resizeHistory.push(event);
    if (this.resizeHistory.length > MAX_RESIZE_HISTORY) {
      this.resizeHistory.shift();
    }
  }

  // ── Dynamic pool resize ──────────────────────────────────────────────

  /**
   * Resize the gRPC stream pool at runtime without restarting the app.
   *
   * - **Scale up**: opens additional streams and appends them to the pool.
   *   No disruption — existing in-flight requests continue on their streams.
   * - **Scale down**: waits for in-flight requests to drain (up to 10s),
   *   then closes excess streams from the tail and resets the round-robin
   *   index if needed. Closed streams flush any SDK-queued records.
   *
   * If the pool hasn't been initialized yet (no ingest request has been
   * made), this just updates the target size for the next initialization.
   *
   * @param newSize - Desired pool size (1–32).
   * @returns Previous and new pool sizes with timing.
   */
  async resize(
    newSize: number,
  ): Promise<{ oldSize: number; newSize: number; durationMs: number }> {
    if (newSize < 1 || newSize > 32) {
      throw new Error(`Pool size must be between 1 and 32, got ${newSize}`);
    }

    const start = performance.now();
    const oldSize = this.streams.length;

    // Pool not yet initialized — just update the target
    if (oldSize === 0 || !this.sdk) {
      this.poolSize = newSize;
      console.log(
        `[ZeroBus] Pool size set to ${newSize} (will apply on next initialization)`,
      );
      return { oldSize: 0, newSize, durationMs: 0 };
    }

    if (newSize === oldSize) {
      return { oldSize, newSize, durationMs: 0 };
    }

    if (newSize > oldSize) {
      // ── Scale UP — open additional streams ──────────────────────
      console.log(`[ZeroBus] Scaling pool UP: ${oldSize} → ${newSize}`);

      const additional = newSize - oldSize;
      const newStreams = await Promise.all(
        Array.from({ length: additional }, (_, i) =>
          this.sdk!.createStream(
            { tableName: this.targetTable },
            this.clientId,
            this.clientSecret,
            { recordType: RecordType.Json },
          ).then((stream: IngestStream) => {
            console.log(
              `[ZeroBus] Stream ${oldSize + i + 1}/${newSize} opened (resize)`,
            );
            return stream;
          }),
        ),
      );
      this.streams.push(...newStreams);
    } else {
      // ── Scale DOWN — drain in-flight, then close excess ─────────
      console.log(
        `[ZeroBus] Scaling pool DOWN: ${oldSize} → ${newSize} (draining in-flight...)`,
      );

      // Wait for in-flight requests to complete — they may hold
      // references to streams we're about to close.
      const drainStart = Date.now();
      while (this.inflight > 0 && Date.now() - drainStart < 10_000) {
        await new Promise((r) => setTimeout(r, 50));
      }
      if (this.inflight > 0) {
        console.warn(
          `[ZeroBus] ${this.inflight} request(s) still in-flight after 10s drain — proceeding with resize`,
        );
      }

      // Remove excess streams from the tail of the pool
      const excess = this.streams.splice(newSize);

      // Reset round-robin index if it's beyond the new pool boundary
      if (this.streamIndex >= newSize) {
        this.streamIndex = 0;
      }

      // Close removed streams (flushes any SDK-queued records)
      await Promise.allSettled(excess.map((s) => s.close()));
      console.log(`[ZeroBus] Closed ${excess.length} excess stream(s)`);
    }

    this.poolSize = newSize;
    const durationMs = Math.round(performance.now() - start);
    console.log(
      `[ZeroBus] Pool resized: ${oldSize} → ${newSize} (${durationMs}ms)`,
    );

    // Record in history (trigger is set by caller via _lastResizeTrigger)
    this.recordResizeEvent({
      timestamp: new Date().toISOString(),
      trigger: this._lastResizeTrigger ?? 'manual',
      oldSize,
      newSize,
      durationMs,
      peakInflight: this._lastResizePeak,
      idleChecks: this._lastResizeIdle,
      callRate: this._lastResizeCallRate,
    });
    this._lastResizeTrigger = null;
    this._lastResizePeak = undefined;
    this._lastResizeIdle = undefined;
    this._lastResizeCallRate = undefined;

    return { oldSize, newSize, durationMs };
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
   * @throws Error if the service is draining (SIGTERM received).
   * @returns The number of records durably ingested.
   */
  async ingestRecords(records: WearablesRecord[]): Promise<number> {
    if (records.length === 0) return 0;

    // Reject new requests during graceful shutdown
    if (this.draining) {
      throw new Error(
        'Service is shutting down — not accepting new ingest requests',
      );
    }

    // Validate env vars before attempting ingestion
    const envCheck = this.checkEnv();
    if (!envCheck.configured) {
      throw new Error(
        `Missing required ZeroBus env vars: ${envCheck.missing.join(', ')}`,
      );
    }

    await this.ensurePool();
    const stream = this.nextStream();

    // Track in-flight requests for graceful shutdown
    this.inflight++;
    if (this.inflight > this.peakInflight) this.peakInflight = this.inflight;
    this.callsSinceLastCheck++;
    try {
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
    } finally {
      this.inflight--;
    }
  }


  // ── Auto-scale management ────────────────────────────────────────────

  /**
   * Enable automatic pool scaling based on load.
   *
   * A background interval checks stream utilization every `checkIntervalMs`:
   *   - **Scale up**: when peak in-flight ≥ stream count (all streams
   *     saturated), adds `scaleUpStep` streams up to `maxSize`.
   *   - **Scale down**: after `IDLE_CHECKS_BEFORE_SCALE_DOWN` consecutive
   *     checks with 0 in-flight, removes `scaleDownStep` streams down
   *     to `minSize`.
   *   - A `cooldownMs` guard prevents resize thrashing.
   */
  enableAutoScale(config: Partial<AutoScaleConfig> = {}): AutoScaleConfig {
    this.autoScaleConfig = { ...AUTO_SCALE_DEFAULTS, ...config };
    this.autoScaleEnabled = true;
    this.lastAutoScaleTime = 0;
    this.peakInflight = 0;
    this.idleChecks = 0;
    this.callsSinceLastCheck = 0;

    // Clear any existing timer before starting a new one
    if (this.autoScaleTimer) clearInterval(this.autoScaleTimer);
    this.autoScaleTimer = setInterval(
      () => void this.checkAutoScale(),
      this.autoScaleConfig.checkIntervalMs,
    );

    console.log(
      `[ZeroBus] Auto-scale enabled (min: ${this.autoScaleConfig.minSize}, max: ${this.autoScaleConfig.maxSize}, ` +
        `interval: ${this.autoScaleConfig.checkIntervalMs}ms, cooldown: ${this.autoScaleConfig.cooldownMs}ms)`,
    );
    return { ...this.autoScaleConfig };
  }

  /** Disable auto-scaling. The pool stays at its current size. */
  disableAutoScale(): void {
    if (this.autoScaleTimer) {
      clearInterval(this.autoScaleTimer);
      this.autoScaleTimer = null;
    }
    this.autoScaleEnabled = false;
    console.log('[ZeroBus] Auto-scale disabled');
  }

  /** Returns current auto-scale configuration, state, and resize history. */
  autoScaleStatus(): {
    enabled: boolean;
    config: AutoScaleConfig;
    peak_inflight: number;
    idle_checks: number;
    history: ResizeEvent[];
  } {
    return {
      enabled: this.autoScaleEnabled,
      config: { ...this.autoScaleConfig },
      peak_inflight: this.peakInflight,
      idle_checks: this.idleChecks,
      history: [...this.resizeHistory],
    };
  }

  /**
   * Background check — called by the auto-scale interval timer.
   * Not meant to be called directly.
   */
  private async checkAutoScale(): Promise<void> {
    if (!this.autoScaleEnabled || this.streams.length === 0 || this.draining) {
      return;
    }

    const now = Date.now();
    const cooldownElapsed =
      now - this.lastAutoScaleTime >= this.autoScaleConfig.cooldownMs;

    // Capture and reset interval metrics
    const currentInflight = this.inflight;
    const peak = Math.max(this.peakInflight, currentInflight);
    const callRate = this.callsSinceLastCheck;
    this.peakInflight = currentInflight; // reset for next interval
    this.callsSinceLastCheck = 0;

    const streamCount = this.streams.length;
    const config = this.autoScaleConfig;

    // ── Scale-up decision ──────────────────────────────────────
    // Two independent triggers (either can fire):
    //   1. Concurrent saturation: peak in-flight ≥ stream count
    //      (multiple callers saturating all streams simultaneously)
    //   2. High call rate: ingestRecords() called ≥ stream count
    //      times since last check (sequential-but-heavy usage, e.g.
    //      load test batches or rapid iOS syncs in sequence)
    const concurrentSaturated = peak >= streamCount;
    const highCallRate = callRate >= streamCount;

    if (
      (concurrentSaturated || highCallRate) &&
      streamCount < config.maxSize &&
      cooldownElapsed
    ) {
      const newSize = Math.min(
        streamCount + config.scaleUpStep,
        config.maxSize,
      );
      const reason = concurrentSaturated
        ? `peak ${peak} in-flight ≥ ${streamCount} streams`
        : `${callRate} calls in interval ≥ ${streamCount} streams`;
      console.log(
        `[ZeroBus/AutoScale] ${reason} — scaling UP: ${streamCount} → ${newSize}`,
      );
      try {
        this._lastResizeTrigger = 'auto-scale-up';
        this._lastResizePeak = peak;
        this._lastResizeCallRate = callRate;
        await this.resize(newSize);
        this.lastAutoScaleTime = now;
      } catch (err) {
        console.error('[ZeroBus/AutoScale] Scale-up failed:', err);
      }
      this.idleChecks = 0;
    } else if (currentInflight === 0 && callRate === 0) {
      // ── Scale-down decision ────────────────────────────────────
      // Require sustained idle: no in-flight AND no calls for
      // IDLE_CHECKS_BEFORE_SCALE_DOWN consecutive checks.
      this.idleChecks++;
      if (
        this.idleChecks >= IDLE_CHECKS_BEFORE_SCALE_DOWN &&
        streamCount > config.minSize &&
        cooldownElapsed
      ) {
        const newSize = Math.max(
          streamCount - config.scaleDownStep,
          config.minSize,
        );
        console.log(
          `[ZeroBus/AutoScale] Idle for ${this.idleChecks} checks — scaling DOWN: ${streamCount} → ${newSize}`,
        );
        try {
          this._lastResizeTrigger = 'auto-scale-down';
          this._lastResizeIdle = this.idleChecks;
          await this.resize(newSize);
          this.lastAutoScaleTime = now;
        } catch (err) {
          console.error('[ZeroBus/AutoScale] Scale-down failed:', err);
        }
        this.idleChecks = 0;
      }
    } else {
      this.idleChecks = 0;
    }
  }

  // ── Health check ─────────────────────────────────────────────────────

  /** Check whether all required env vars are present. */
  checkEnv(): { configured: boolean; missing: string[] } {
    const missing = ENV_KEYS.filter((k) => !process.env[k]);
    return { configured: missing.length === 0, missing: [...missing] };
  }

  /** Stream pool and drain status for the health check endpoint. */
  poolStatus(): {
    pool_size: number;
    active_streams: number;
    initialized: boolean;
    inflight_requests: number;
    draining: boolean;
  } {
    return {
      pool_size: this.poolSize,
      active_streams: this.streams.length,
      initialized: this.streams.length > 0,
      inflight_requests: this.inflight,
      draining: this.draining,
      auto_scale: {
        enabled: this.autoScaleEnabled,
        min_size: this.autoScaleConfig.minSize,
        max_size: this.autoScaleConfig.maxSize,
      },
    };
  }

  // ── Graceful shutdown ────────────────────────────────────────────────

  /**
   * Drain in-flight requests, then close all streams and release resources.
   *
   * Shutdown sequence:
   *   1. Set draining=true — ingestRecords() rejects new calls immediately
   *   2. Poll until inflight reaches 0 (or DRAIN_TIMEOUT_MS elapses)
   *      This gives in-flight Express handlers time to finish their
   *      ingestRecordOffset() + waitForOffset() calls.
   *   3. Close all streams — each stream.close() flushes any records
   *      still queued in the SDK's internal buffer and waits for final
   *      acknowledgments from the ZeroBus server.
   *
   * After step 3, every record that was accepted by ingestRecords()
   * before SIGTERM is guaranteed durably committed to the Delta table.
   */
  async close(): Promise<void> {
    this.draining = true;
    this.disableAutoScale();

    // ── Step 1: Drain in-flight requests ────────────────────────────
    if (this.inflight > 0) {
      console.log(
        `[ZeroBus] Draining ${this.inflight} in-flight request(s) (timeout: ${DRAIN_TIMEOUT_MS}ms)...`,
      );

      const drainStart = Date.now();
      while (
        this.inflight > 0 &&
        Date.now() - drainStart < DRAIN_TIMEOUT_MS
      ) {
        await new Promise((r) => setTimeout(r, DRAIN_POLL_INTERVAL_MS));
        if (this.inflight > 0) {
          console.log(
            `[ZeroBus] Still draining — ${this.inflight} request(s) in-flight`,
          );
        }
      }

      if (this.inflight > 0) {
        console.warn(
          `[ZeroBus] Drain timeout reached — ${this.inflight} request(s) still in-flight, proceeding with stream close`,
        );
      } else {
        console.log('[ZeroBus] All in-flight requests drained');
      }
    }

    // ── Step 2: Close all streams (flushes SDK-queued records) ──────
    if (this.streams.length > 0) {
      console.log(`[ZeroBus] Closing ${this.streams.length} stream(s)...`);
      await Promise.allSettled(this.streams.map((s) => s.close()));
      console.log('[ZeroBus] All streams closed — records durably committed');
    }

    this.streams = [];
    this.streamIndex = 0;
    this.sdk = null;
  }
}

// ── Singleton export ─────────────────────────────────────────────────────

/** Shared instance — used by all Express route handlers. */
export const zeroBusService = new ZeroBusService();
