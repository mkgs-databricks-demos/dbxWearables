// ZeroBus Ingest Service — Singleton
//
// Manages the ZeroBus SDK lifecycle (connection, stream, shutdown) and
// exposes a record-builder + batch-ingest API consumed by Express routes.
//
// Environment variables (injected via app.yaml valueFrom directives):
//   ZEROBUS_ENDPOINT      — ZeroBus Ingest server endpoint
//   ZEROBUS_WORKSPACE_URL — Databricks workspace URL
//   ZEROBUS_TARGET_TABLE  — Fully qualified bronze table name
//   ZEROBUS_CLIENT_ID     — ZeroBus SPN application_id (OAuth M2M)
//   ZEROBUS_CLIENT_SECRET — ZeroBus SPN OAuth secret
//
// Table schema (hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus):
//   record_id   STRING  NOT NULL  — Server-generated GUID (PK)
//   ingested_at TIMESTAMP         — Epoch microseconds
//   body        VARIANT           — Raw NDJSON line as JSON-encoded string
//   headers     VARIANT           — HTTP request headers as JSON-encoded string
//   record_type STRING            — From X-Record-Type header

import { ZerobusSdk, RecordType } from '@databricks/zerobus-ingest-sdk';
import crypto from 'node:crypto';

// ── Types matching the bronze table schema ───────────────────────────────

export interface WearablesRecord {
  record_id: string;    // NOT NULL PK — crypto.randomUUID()
  ingested_at: number;  // TIMESTAMP   — epoch microseconds (Date.now() * 1000)
  body: string;         // VARIANT     — JSON.stringify(parsedNdjsonLine)
  headers: string;      // VARIANT     — JSON.stringify(httpHeaders)
  record_type: string;  // STRING      — e.g. "samples", "workouts", "sleep"
}

// ── Required env var names ───────────────────────────────────────────────

const ENV_KEYS = [
  'ZEROBUS_ENDPOINT',
  'ZEROBUS_WORKSPACE_URL',
  'ZEROBUS_TARGET_TABLE',
  'ZEROBUS_CLIENT_ID',
  'ZEROBUS_CLIENT_SECRET',
] as const;

// ── Service class ────────────────────────────────────────────────────────

class ZeroBusService {
  private sdk: ZerobusSdk | null = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private stream: any = null;
  private initPromise: Promise<void> | null = null;

  // ── Lazy initialization ──────────────────────────────────────────────

  /**
   * Ensure the SDK and stream are ready. First call creates the stream;
   * concurrent calls share the same initialization promise.
   */
  async ensureStream(): Promise<void> {
    if (this.stream) return;
    if (this.initPromise) return this.initPromise;
    this.initPromise = this._initialize();
    try {
      await this.initPromise;
    } finally {
      this.initPromise = null;
    }
  }

  private async _initialize(): Promise<void> {
    const endpoint     = process.env.ZEROBUS_ENDPOINT!;
    const workspaceUrl = process.env.ZEROBUS_WORKSPACE_URL!;
    const targetTable  = process.env.ZEROBUS_TARGET_TABLE!;
    const clientId     = process.env.ZEROBUS_CLIENT_ID!;
    const clientSecret = process.env.ZEROBUS_CLIENT_SECRET!;

    // Validate all required env vars are present
    const missing = ENV_KEYS.filter((k) => !process.env[k]);
    if (missing.length > 0) {
      throw new Error(`Missing required ZeroBus env vars: ${missing.join(', ')}`);
    }

    console.log(`[ZeroBus] Initializing SDK → ${endpoint}`);
    this.sdk = new ZerobusSdk(endpoint, workspaceUrl);

    this.stream = await this.sdk.createStream(
      { tableName: targetTable },
      clientId,
      clientSecret,
      { recordType: RecordType.Json },
    );

    console.log(`[ZeroBus] Stream opened → ${targetTable}`);
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
  ): WearablesRecord {
    return {
      record_id:   crypto.randomUUID(),
      ingested_at: Date.now() * 1000,       // ms → μs
      body:        JSON.stringify(body),      // VARIANT — JSON-encoded string
      headers:     JSON.stringify(headers),   // VARIANT — JSON-encoded string
      record_type: recordType,
    };
  }

  // ── Batch ingest ─────────────────────────────────────────────────────

  /**
   * Ingest an array of pre-built records and block until the last record
   * is durably committed in the bronze table.
   *
   * @returns The number of records ingested.
   */
  async ingestRecords(records: WearablesRecord[]): Promise<number> {
    await this.ensureStream();
    if (records.length === 0) return 0;

    let lastOffset = BigInt(0);
    for (const record of records) {
      lastOffset = await this.stream.ingestRecordOffset(record);
    }

    // Block until the last offset is durable
    await this.stream.waitForOffset(lastOffset);
    return records.length;
  }

  // ── Health check ─────────────────────────────────────────────────────

  /** Check whether all required env vars are present. */
  checkEnv(): { configured: boolean; missing: string[] } {
    const missing = ENV_KEYS.filter((k) => !process.env[k]);
    return { configured: missing.length === 0, missing: [...missing] };
  }

  // ── Graceful shutdown ────────────────────────────────────────────────

  async close(): Promise<void> {
    if (this.stream) {
      try {
        await this.stream.close();
        console.log('[ZeroBus] Stream closed');
      } catch (err) {
        console.error('[ZeroBus] Error closing stream:', err);
      }
      this.stream = null;
    }
    this.sdk = null;
  }
}

// ── Singleton export ─────────────────────────────────────────────────────

/** Shared instance — used by all Express route handlers. */
export const zeroBusService = new ZeroBusService();
