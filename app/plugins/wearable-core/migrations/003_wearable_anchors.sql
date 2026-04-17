-- Per-user, per-provider, per-record-type sync anchors.
-- Mirrors the iOS HealthKit SyncStateRepository so every source uses the
-- same "what have we already ingested?" contract.

CREATE TABLE IF NOT EXISTS wearable_anchors (
  user_id                  UUID        NOT NULL REFERENCES app_users(user_id) ON DELETE CASCADE,
  provider                 TEXT        NOT NULL,
  record_type              TEXT        NOT NULL,
  last_start_time_seconds  BIGINT,
  last_backfill_through    DATE,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, provider, record_type)
);
