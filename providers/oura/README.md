# Oura connector (stub)

Cloud-API connector for [Oura](https://cloud.ouraring.com/v2/docs). Not yet implemented.

## What this connector will provide

- **Auth:** OAuth 2.0 PKCE. Scopes: `email personal daily heartrate workout session tag spo2 ring_configuration`.
- **Webhook:** Oura v2 webhooks (Ring 3+ required; tier-gated).
- **Poll:** REST API (`/v2/usercollection/daily_sleep`, `/v2/usercollection/daily_activity`, `/v2/usercollection/heartrate`, `/v2/usercollection/workout`, etc.).

## What you need to implement

1. **AppKit plugin** at [`app/plugins/oura/`](../../app/plugins/oura/README.md):
   - Scaffold via `npx @databricks/appkit plugin create --path app/plugins/oura --name oura`.
   - Declare manifest resources (optional): `clientId`, `clientSecret`, `webhookSecret`.
   - Implement `OuraConnector extends BaseOAuth2Connector`.
   - Register with `AppKit.wearableCore.connectorRegistry` in `setup()`.
2. **Pull connector** at `providers/oura/pull/`:
   - Satisfies `providers.common.connector_protocol.ConnectorProtocol`.
   - `pull_batch(user_id, provider_user_id, range)` iterates the v2 usercollection endpoints.
3. **Silver normalizer** at `providers/oura/silver/normalizer.py`:
   - Suggested `metric_type` values: `sleep_score`, `readiness_score`, `activity_score`, `hrv_rmssd`, `resting_heart_rate`, `temperature_deviation`.

## Record types

- `oura_daily_sleep`, `oura_daily_activity`, `oura_daily_readiness`
- `oura_heartrate`, `oura_spo2`, `oura_workout`
- `oura_ring_configuration` (low-churn)

## References

- [Oura Cloud v2 API](https://cloud.ouraring.com/v2/docs)
- [Oura webhooks](https://cloud.ouraring.com/docs/webhooks)
- Contract: [`providers/common/connector_protocol.py`](../common/connector_protocol.py)
