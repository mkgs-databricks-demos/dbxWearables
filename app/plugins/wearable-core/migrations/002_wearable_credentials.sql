-- Per-user, per-provider OAuth credentials.
-- Token columns are envelope-encrypted via the signingKey resource.
-- The (user_id, provider) UNIQUE constraint enforces one active credential
-- per user+provider; re-auth overwrites via upsert.

CREATE TABLE IF NOT EXISTS wearable_credentials (
  credential_id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID        NOT NULL REFERENCES app_users(user_id) ON DELETE CASCADE,
  provider                TEXT        NOT NULL,
  provider_user_id        TEXT        NOT NULL,
  access_token_encrypted  BYTEA       NOT NULL,
  refresh_token_encrypted BYTEA,
  token_expires_at        TIMESTAMPTZ,
  scopes                  TEXT[]      NOT NULL DEFAULT '{}',
  enrolled_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at              TIMESTAMPTZ,
  UNIQUE (provider, provider_user_id),
  UNIQUE (user_id, provider)
);

CREATE INDEX IF NOT EXISTS wearable_credentials_active_idx
  ON wearable_credentials (provider, user_id)
  WHERE revoked_at IS NULL;
