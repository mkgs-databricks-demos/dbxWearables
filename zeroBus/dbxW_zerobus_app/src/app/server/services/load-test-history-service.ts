// Load Test History Service — Lakebase CRUD for Load Test Runs
//
// Manages structured load test history in Lakebase (Postgres). Tables are
// auto-replicated to Unity Catalog via Lakehouse Sync (wal2delta CDC).
//
// Tables:
//   app.load_test_runs          — one row per test run
//   app.load_test_type_results  — one row per record type per run
//
// The service is initialized lazily on first use. Table setup includes
// REPLICA IDENTITY FULL for Lakehouse Sync compatibility.

import type { TypeMetrics } from './synthetic-data-service.js';

// ── Lakebase query interface ──────────────────────────────────────────

interface LakebaseClient {
  query(text: string, params?: unknown[]): Promise<{ rows: Record<string, unknown>[] }>;
}

let lakebaseClient: LakebaseClient | null = null;

/** Called once from server.ts after AppKit initializes */
export function setLakebaseClient(client: LakebaseClient) {
  lakebaseClient = client;
}

function db(): LakebaseClient {
  if (!lakebaseClient) {
    throw new Error('[LoadTestHistory] Lakebase client not initialized. Call setLakebaseClient() first.');
  }
  return lakebaseClient;
}

// ── SQL DDL ───────────────────────────────────────────────────────────

const SETUP_SCHEMA_SQL = `CREATE SCHEMA IF NOT EXISTS app`;

const CREATE_RUNS_TABLE_SQL = `
CREATE TABLE IF NOT EXISTS app.load_test_runs (
  run_id            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  user_id           TEXT NOT NULL,
  user_ip           TEXT,
  started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at      TIMESTAMPTZ,
  duration_ms       INT,
  status            TEXT NOT NULL DEFAULT 'running',
  error_message     TEXT,
  preset_label      TEXT,
  batch_size        INT NOT NULL,
  total_payloads    INT NOT NULL,
  total_records     INT,
  records_per_sec   INT,
  pool_size_start   INT,
  pool_size_end     INT,
  auto_scale_enabled BOOLEAN DEFAULT false,
  auto_scale_min    INT,
  auto_scale_max    INT
)`;

const CREATE_TYPE_RESULTS_TABLE_SQL = `
CREATE TABLE IF NOT EXISTS app.load_test_type_results (
  run_id            TEXT NOT NULL REFERENCES app.load_test_runs(run_id) ON DELETE CASCADE,
  record_type       TEXT NOT NULL,
  payload_count     INT NOT NULL DEFAULT 0,
  record_count      INT,
  duration_ms       INT,
  records_per_sec   INT,
  PRIMARY KEY (run_id, record_type)
)`;

// REPLICA IDENTITY FULL is required for Lakehouse Sync (wal2delta) to
// capture the full row on UPDATE/DELETE operations. Without it, only
// the primary key columns would be included in change events.
const REPLICA_IDENTITY_RUNS_SQL = `
ALTER TABLE app.load_test_runs REPLICA IDENTITY FULL`;

const REPLICA_IDENTITY_TYPE_RESULTS_SQL = `
ALTER TABLE app.load_test_type_results REPLICA IDENTITY FULL`;

const TABLE_EXISTS_SQL = `
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'app' AND table_name = 'load_test_runs'`;

// ── Types ─────────────────────────────────────────────────────────────

export interface CreateRunParams {
  userId: string;
  userIp: string;
  presetLabel: string;
  batchSize: number;
  totalPayloads: number;
  poolSizeStart: number;
  autoScaleEnabled: boolean;
  autoScaleMin?: number;
  autoScaleMax?: number;
  configuredTypes: Partial<Record<string, number>>;
}

export interface CompleteRunParams {
  status: 'complete' | 'error' | 'aborted';
  totalRecords?: number;
  recordsPerSec?: number;
  durationMs?: number;
  poolSizeEnd?: number;
  errorMessage?: string;
}

export interface RunWithTypes {
  run: Record<string, unknown>;
  typeResults: Record<string, unknown>[];
}

// ── Service ───────────────────────────────────────────────────────────

class LoadTestHistoryService {
  private initialized = false;

  /**
   * Ensure Lakebase tables exist. Called lazily on first write.
   * Idempotent — safe to call multiple times.
   */
  async ensureTables(): Promise<void> {
    if (this.initialized) return;

    try {
      const { rows } = await db().query(TABLE_EXISTS_SQL);
      if (rows.length > 0) {
        console.log('[LoadTestHistory] Tables already exist, skipping setup');
        this.initialized = true;
        return;
      }

      await db().query(SETUP_SCHEMA_SQL);
      await db().query(CREATE_RUNS_TABLE_SQL);
      await db().query(CREATE_TYPE_RESULTS_TABLE_SQL);
      await db().query(REPLICA_IDENTITY_RUNS_SQL);
      await db().query(REPLICA_IDENTITY_TYPE_RESULTS_SQL);
      console.log('[LoadTestHistory] Created tables with REPLICA IDENTITY FULL');
      this.initialized = true;
    } catch (err) {
      console.error('[LoadTestHistory] Table setup failed:', (err as Error).message);
      throw err;
    }
  }

  /**
   * Create a new load test run. Returns the generated run_id.
   */
  async createRun(params: CreateRunParams): Promise<string> {
    await this.ensureTables();

    const { rows } = await db().query(
      `INSERT INTO app.load_test_runs (
        user_id, user_ip, preset_label, batch_size, total_payloads,
        pool_size_start, auto_scale_enabled, auto_scale_min, auto_scale_max
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING run_id`,
      [
        params.userId,
        params.userIp,
        params.presetLabel,
        params.batchSize,
        params.totalPayloads,
        params.poolSizeStart,
        params.autoScaleEnabled,
        params.autoScaleMin ?? null,
        params.autoScaleMax ?? null,
      ],
    );

    const runId = rows[0].run_id as string;

    // Insert initial type result rows (one per configured type)
    for (const [recordType, payloadCount] of Object.entries(params.configuredTypes)) {
      if (payloadCount && payloadCount > 0) {
        await db().query(
          `INSERT INTO app.load_test_type_results (run_id, record_type, payload_count)
           VALUES ($1, $2, $3)`,
          [runId, recordType, payloadCount],
        );
      }
    }

    console.log(`[LoadTestHistory] Created run ${runId} (${params.presetLabel}, user: ${params.userId})`);
    return runId;
  }

  /**
   * Update a run with final results or error status.
   */
  async completeRun(runId: string, params: CompleteRunParams): Promise<void> {
    await db().query(
      `UPDATE app.load_test_runs SET
        status = $2,
        completed_at = NOW(),
        duration_ms = $3,
        total_records = $4,
        records_per_sec = $5,
        pool_size_end = $6,
        error_message = $7
      WHERE run_id = $1`,
      [
        runId,
        params.status,
        params.durationMs ?? null,
        params.totalRecords ?? null,
        params.recordsPerSec ?? null,
        params.poolSizeEnd ?? null,
        params.errorMessage ?? null,
      ],
    );

    console.log(`[LoadTestHistory] Updated run ${runId}: status=${params.status}`);
  }

  /**
   * Upsert per-type results from the final IngestResult.perType array.
   */
  async upsertTypeResults(runId: string, perType: TypeMetrics[]): Promise<void> {
    for (const t of perType) {
      const recPerSec = t.durationMs > 0
        ? Math.round((t.recordCount / t.durationMs) * 1000)
        : 0;

      await db().query(
        `UPDATE app.load_test_type_results SET
          record_count = $3,
          duration_ms = $4,
          records_per_sec = $5
        WHERE run_id = $1 AND record_type = $2`,
        [runId, t.recordType, t.recordCount, t.durationMs, recPerSec],
      );
    }
  }

  /**
   * List runs, most recent first. Includes per-type breakdown via lateral join.
   */
  async listRuns(limit: number, offset: number): Promise<Record<string, unknown>[]> {
    await this.ensureTables();

    const { rows } = await db().query(
      `SELECT
        r.*,
        COALESCE(
          (SELECT json_agg(json_build_object(
            'record_type', tr.record_type,
            'payload_count', tr.payload_count,
            'record_count', tr.record_count,
            'duration_ms', tr.duration_ms,
            'records_per_sec', tr.records_per_sec
          ) ORDER BY tr.record_type)
          FROM app.load_test_type_results tr
          WHERE tr.run_id = r.run_id),
          '[]'::json
        ) AS type_results
      FROM app.load_test_runs r
      ORDER BY r.started_at DESC
      LIMIT $1 OFFSET $2`,
      [limit, offset],
    );

    return rows;
  }

  /**
   * Get a single run by ID with per-type breakdown.
   */
  async getRun(runId: string): Promise<RunWithTypes | null> {
    const { rows: runRows } = await db().query(
      `SELECT * FROM app.load_test_runs WHERE run_id = $1`,
      [runId],
    );

    if (runRows.length === 0) return null;

    const { rows: typeRows } = await db().query(
      `SELECT * FROM app.load_test_type_results
       WHERE run_id = $1
       ORDER BY record_type`,
      [runId],
    );

    return { run: runRows[0], typeResults: typeRows };
  }

  /**
   * Remove a run and its type results (CASCADE handles the FK).
   * Returns true if a row was actually removed.
   */
  async deleteRun(runId: string): Promise<boolean> {
    const { rows } = await db().query(
      `WITH removed AS (
        SELECT run_id FROM app.load_test_runs WHERE run_id = $1 FOR UPDATE
      )
      SELECT run_id FROM removed`,
      [runId],
    );

    if (rows.length === 0) return false;

    await db().query(
      `DELETE FROM app.load_test_runs WHERE run_id = $1`,
      [runId],
    );
    return true;
  }
}

export const loadTestHistoryService = new LoadTestHistoryService();
