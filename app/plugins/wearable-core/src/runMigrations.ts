/**
 * Shared migration runner used by every plugin that owns Lakebase tables.
 *
 * Reads numbered .sql files (001_*.sql, 002_*.sql, ...) from a directory
 * and applies any not yet recorded in the appkit_migrations tracking table
 * for the caller's namespace. Each migration runs in its own transaction.
 *
 * Usage from any plugin's setup():
 *
 *   import { runMigrations } from "../../wearable-core/src/runMigrations";
 *   await runMigrations(this.appkit.lakebase, "my-plugin", __dirname + "/migrations");
 *
 * Or from within the wearable-core plugin itself:
 *
 *   await this.appkit.wearableCore.runMigrations("my-plugin", dir);
 */
import { promises as fs } from "node:fs";
import * as path from "node:path";

interface LakebaseLike {
  query: (sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }>;
}

interface Logger {
  info: (msg: string, meta?: object) => void;
  warn: (msg: string, meta?: object) => void;
}

const TRACKING_TABLE = `
  CREATE TABLE IF NOT EXISTS appkit_migrations (
    namespace  TEXT        NOT NULL,
    version    TEXT        NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (namespace, version)
  )
`;

export async function runMigrations(
  lakebase: LakebaseLike,
  namespace: string,
  migrationsDir: string,
  logger?: Logger,
): Promise<{ applied: string[]; skipped: string[] }> {
  await lakebase.query(TRACKING_TABLE);

  const files = (await fs.readdir(migrationsDir))
    .filter((f) => f.endsWith(".sql"))
    .sort();

  const { rows } = await lakebase.query(
    "SELECT version FROM appkit_migrations WHERE namespace = $1",
    [namespace],
  );
  const applied = new Set(
    (rows as Array<{ version: string }>).map((r) => r.version),
  );

  const appliedNow: string[] = [];
  const skipped: string[] = [];

  for (const file of files) {
    const version = file.replace(/\.sql$/, "");
    if (applied.has(version)) {
      skipped.push(version);
      continue;
    }
    const sql = await fs.readFile(path.join(migrationsDir, file), "utf8");
    try {
      await lakebase.query("BEGIN");
      await lakebase.query(sql);
      await lakebase.query(
        "INSERT INTO appkit_migrations (namespace, version) VALUES ($1, $2)",
        [namespace, version],
      );
      await lakebase.query("COMMIT");
      appliedNow.push(version);
      logger?.info("appkit.migration.applied", { namespace, version });
    } catch (err) {
      await lakebase.query("ROLLBACK");
      logger?.warn("appkit.migration.failed", {
        namespace,
        version,
        error: String(err),
      });
      throw err;
    }
  }

  return { applied: appliedNow, skipped };
}
