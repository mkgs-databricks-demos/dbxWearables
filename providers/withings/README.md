# Withings connector (stub)

Cloud-API connector for [Withings](https://developer.withings.com/). Not yet implemented.

## What this connector will provide

- **Auth:** OAuth 2.0 (Authorization Code). Scopes: `user.info user.metrics user.activity`.
- **Webhook:** Withings Notify API — you register a callback URL per `appli` (measurement category), Withings POSTs a ping, you fetch the detail via REST.
- **Poll:** REST API (`/measure?action=getmeas`, `/v2/sleep?action=getsummary`, `/v2/heart?action=list`, etc.).

## What you need to implement

1. **AppKit plugin** at [`app/plugins/withings/`](../../app/plugins/withings/README.md):
   - Scaffold via `npx @databricks/appkit plugin create --path app/plugins/withings --name withings`.
   - Manifest resources (optional): `clientId`, `clientSecret`.
   - Implement `WithingsConnector extends BaseOAuth2Connector`.
   - Register Notify subscriptions (`appli=1,4,16,44,50,51,52,54,...`) per user after OAuth.
2. **Pull connector** at `providers/withings/pull/`.
3. **Silver normalizer** at `providers/withings/silver/normalizer.py`:
   - Suggested `metric_type` values: `weight`, `body_fat_pct`, `blood_pressure_systolic`, `blood_pressure_diastolic`, `heart_rate_resting`, `sleep_duration`, `spo2`.

## Record types

- `withings_body_measure` (weight, body composition, BP)
- `withings_sleep`, `withings_heart_ecg`
- `withings_activity`, `withings_spo2`

## References

- [Withings Developer](https://developer.withings.com/)
- [Withings Notify API](https://developer.withings.com/developer-guide/notifications/)
- Contract: [`providers/common/connector_protocol.py`](../common/connector_protocol.py)
