-- App-scoped identity: one row per end-user of the dbxWearables deployment.
-- external_id is whatever the consuming company uses to identify a user
-- (SSO sub, employee ID, patient MRN, etc.). Provider-specific user IDs
-- live on wearable_credentials, not here.

CREATE TABLE IF NOT EXISTS app_users (
  user_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id    TEXT        UNIQUE NOT NULL,
  email          TEXT,
  display_name   TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deactivated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS app_users_email_idx ON app_users (email) WHERE email IS NOT NULL;
