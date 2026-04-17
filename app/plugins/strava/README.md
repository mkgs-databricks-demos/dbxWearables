# `strava` plugin — stub (Tier 3)

Not yet implemented. Scaffold with:

```bash
npx @databricks/appkit plugin create --placement in-repo --path app/plugins/strava --name strava
```

See the domain-side contributor guide at [`providers/strava/README.md`](../../../providers/strava/README.md) for why Strava is activity-centric rather than vitals-centric.

## Contract summary

- **Base class:** [`BaseOAuth2Connector`](../wearable-core/src/baseOAuth2Connector.ts).
- **Manifest resources:** `clientId`, `clientSecret`, `webhookVerifyToken`.
- **`resolveProviderUserId`:** `GET https://www.strava.com/api/v3/athlete` with bearer, return `id`.
- **Webhook subscription:** app-level (not per-user). Registered once via `POST /api/v3/push_subscriptions`; Strava issues a `GET /webhook` verification round-trip during setup. `handleWebhook` receives `{ aspect_type, object_id, owner_id, ... }` events and fetches detail from `/activities/{id}`.
- **Register** with `AppKit.wearableCore.connectorRegistry` in `setup()`.
