# `withings` plugin — stub (Tier 3)

Not yet implemented. Scaffold with:

```bash
npx @databricks/appkit plugin create --placement in-repo --path app/plugins/withings --name withings
```

See the domain-side contributor guide at [`providers/withings/README.md`](../../../providers/withings/README.md).

## Contract summary

- **Base class:** [`BaseOAuth2Connector`](../wearable-core/src/baseOAuth2Connector.ts).
- **Manifest resources:** `clientId`, `clientSecret` (Withings Notify API uses a callback URL verified by round-trip; no shared webhook secret).
- **`resolveProviderUserId`:** `POST https://wbsapi.withings.net/v2/user?action=getdevice` with bearer; userid is returned on the token response directly (`userid`).
- **Notify subscription setup:** after OAuth callback, POST `action=subscribe` once per `appli` category the deployer cares about (1=weight, 4=BP, 16=activity, 44=sleep, 50=heart, 51=temperature, 52=BMI, 54=SpO2).
- **Register** with `AppKit.wearableCore.connectorRegistry` in `setup()`.
