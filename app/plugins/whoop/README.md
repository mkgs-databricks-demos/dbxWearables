# `whoop` plugin — stub (Tier 3)

Not yet implemented. Scaffold with:

```bash
npx @databricks/appkit plugin create --placement in-repo --path app/plugins/whoop --name whoop
```

See the domain-side contributor guide at [`providers/whoop/README.md`](../../../providers/whoop/README.md) for record types, API endpoints, and silver normalizer expectations.

## Contract summary

- **Base class:** [`BaseOAuth2Connector`](../wearable-core/src/baseOAuth2Connector.ts).
- **Manifest resources:** `clientId`, `clientSecret`, `webhookSecret` (all optional, promoted to required via `getResourceRequirements({ enabled: true })`).
- **`resolveProviderUserId`:** hit `https://api.prod.whoop.com/developer/v2/user/profile/basic` with the bearer token, return `user_id`.
- **Webhook verification:** HMAC-SHA256 of the body with the webhook secret, constant-time compare against `X-WHOOP-Signature`.
- **Register** with `AppKit.wearableCore.connectorRegistry` in `setup()`.
