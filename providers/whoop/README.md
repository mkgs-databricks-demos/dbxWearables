# Whoop connector (stub)

Cloud-API connector for [Whoop](https://developer.whoop.com/). Not yet implemented.

## What this connector will provide

- **Auth:** OAuth 2.0 (Authorization Code). Scopes: `read:recovery read:sleep read:workout read:cycles read:profile`.
- **Webhook:** Whoop v2 webhooks (`POST /webhook`) for recovery, sleep, and workout events.
- **Poll:** REST API (`/v2/cycle`, `/v2/sleep`, `/v2/recovery`, `/v2/activity`).

## What you need to implement

1. **AppKit plugin** at [`app/plugins/whoop/`](../../app/plugins/whoop/README.md):
   - Scaffold via `npx @databricks/appkit plugin create --path app/plugins/whoop --name whoop`.
   - Declare manifest resources (optional): `clientId`, `clientSecret`, `webhookSecret`.
   - Implement `WhoopConnector extends BaseOAuth2Connector` (most of the work is already in the base class).
   - Register with `AppKit.wearableCore.connectorRegistry` in `setup()`.
2. **Pull connector** at `providers/whoop/pull/`:
   - A class satisfying `providers.common.connector_protocol.ConnectorProtocol`.
   - `pull_batch(user_id, provider_user_id, range)` calls the Whoop v2 API.
   - Register in `providers/whoop/pull/__init__.py` via `register_connector(...)`.
3. **Silver normalizer** at `providers/whoop/silver/normalizer.py`:
   - Maps bronze VARIANT body to `providers.common.silver.HealthEvent` rows.
   - Suggested `metric_type` values: `recovery_score`, `hrv_rmssd`, `sleep_score`, `strain_score`, `workout_calories`.

## Record types (bronze `X-Record-Type` header)

- `whoop_recovery` — daily recovery + HRV summary
- `whoop_sleep` — sleep cycles
- `whoop_workout` — individual workouts
- `whoop_cycle` — physiological cycle (day-scope container)
- `whoop_profile` — profile metadata (low-churn)

## References

- [Whoop Developer Portal](https://developer.whoop.com/)
- [Whoop API reference](https://developer.whoop.com/api/)
- Contract: [`providers/common/connector_protocol.py`](../common/connector_protocol.py)
- Contract: [`app/plugins/wearable-core/README.md`](../../app/plugins/wearable-core/README.md)
