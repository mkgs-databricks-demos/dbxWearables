# `oura` plugin — stub (Tier 3)

Not yet implemented. Scaffold with:

```bash
npx @databricks/appkit plugin create --placement in-repo --path app/plugins/oura --name oura
```

See the domain-side contributor guide at [`providers/oura/README.md`](../../../providers/oura/README.md).

## Contract summary

- **Base class:** [`BaseOAuth2Connector`](../wearable-core/src/baseOAuth2Connector.ts) (PKCE).
- **Manifest resources:** `clientId`, `clientSecret`, `webhookSecret`.
- **`resolveProviderUserId`:** `GET https://api.ouraring.com/v2/usercollection/personal_info` with bearer, return `id`.
- **Webhook verification:** Oura v2 webhooks HMAC-SHA256 signed header.
- **Register** with `AppKit.wearableCore.connectorRegistry` in `setup()`.
