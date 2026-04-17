# `fitbit` plugin — stub (Tier 3)

Not yet implemented. Scaffold with:

```bash
npx @databricks/appkit plugin create --placement in-repo --path app/plugins/fitbit --name fitbit
```

## Contract

- **Base class:** [`BaseOAuth2Connector`](../wearable-core/src/baseOAuth2Connector.ts) — Fitbit uses OAuth 2.0 + PKCE.
- **Scopes (typical):** `activity heartrate location nutrition profile settings sleep weight`.
- **Webhook:** Fitbit Subscription API. Register your app as a Subscriber, pick collection types (`activities`, `body`, `foods`, `sleep`, `userRevokedAccess`).
- **Poll:** Fitbit Web API (`/1.2/user/-/sleep/date/...`, `/1/user/-/activities/date/...`).

## What you need to implement

1. **Manifest resources** (optional, mirror `garmin/`): `clientId`, `clientSecret`, `subscriberVerificationCode`.
2. **`FitbitConnector`** under `src/fitbitConnector.ts` extending `BaseOAuth2Connector`:
   - `resolveProviderUserId(accessToken)` hits `https://api.fitbit.com/1/user/-/profile.json` and returns `user.encodedId`.
   - `verifyWebhook(req)` validates the `X-Fitbit-Signature` header (HMAC-SHA1 of body with `subscriberVerificationCode`).
   - `handleWebhook(req)` iterates the notification array, fetches the updated resource via the Web API using the stored access token, and writes via `bronzeWriter`.
3. **Routes** under `src/routes/`: `oauth.ts`, `webhook.ts`, `revoke.ts` (mirroring `app/plugins/garmin/src/routes/`).
4. **Register** in `setup()` via `AppKit.wearableCore.connectorRegistry.register(this.connector)`.
5. **Add** `fitbit()` to the plugins list in `server/server.ts`.
6. **Implement** the Python pull side at `providers/fitbit/pull/` and the silver normalizer at `providers/fitbit/silver/normalizer.py`.

## Record types

- `fitbit_activity_daily`, `fitbit_heart_intraday`, `fitbit_sleep`, `fitbit_body`, `fitbit_food`

## References

- [Fitbit Web API](https://dev.fitbit.com/build/reference/web-api/)
- [Fitbit Subscription API](https://dev.fitbit.com/build/reference/web-api/subscription/)
- Domain stub: [`providers/fitbit/`](../../../providers/fitbit/)
