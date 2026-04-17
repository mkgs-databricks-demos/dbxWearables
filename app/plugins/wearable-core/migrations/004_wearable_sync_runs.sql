-- Observability: one row per sync run (webhook delivery, pull batch, or backfill).
-- Consumed by the AI/BI dashboards and by the fanout job's rate-limit-aware
-- circuit breaker.

CREATE TABLE IF NOT EXISTS wearable_sync_runs (
  run_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL,
  provider     TEXT        NOT NULL,
  record_type  TEXT,
  mode         TEXT        NOT NULL CHECK (mode IN ('webhook', 'pull', 'backfill', 'phone_sdk')),
  started_at   TIMESTAMPTZ NOT NULL,
  finished_at  TIMESTAMPTZ,
  rows         INTEGER,
  status       TEXT        NOT NULL CHECK (status IN ('ok', 'error', 'rate_limited', 'skipped')),
  error        TEXT
);

CREATE INDEX IF NOT EXISTS wearable_sync_runs_user_idx
  ON wearable_sync_runs (user_id, provider, started_at DESC);

CREATE INDEX IF NOT EXISTS wearable_sync_runs_status_idx
  ON wearable_sync_runs (status, started_at DESC)
  WHERE status IN ('error', 'rate_limited');
