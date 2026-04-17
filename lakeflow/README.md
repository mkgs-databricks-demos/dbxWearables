# Lakeflow — cross-provider pull fanout

One fan-out job powers the pull-based ingestion path for every cloud-API connector. It reads enrolled users from the Lakebase `wearable_credentials` table (populated by the AppKit gateway when users link a provider), groups by provider, and dispatches to each provider's Python `ConnectorProtocol` implementation.

No vendor-specific job. When a new connector goes live, drop a class into `providers/<name>/pull/__init__.py` that registers itself via `providers.common.connector_protocol.register_connector(...)`. The fanout picks it up automatically.

## Notebooks

| Notebook | Purpose |
| --- | --- |
| `wearable_daily_fanout.ipynb` | Scheduled daily pull for every (user, provider) pair. Rate-limit-aware per provider. |
| `wearable_backfill_fanout.ipynb` | On-demand backfill for a date range and an optional user / provider filter. |

## How it discovers connectors

```python
from providers.common.connector_protocol import get_connector, list_registered
import providers.garmin.pull  # side-effect: register_connector(GarminPullConnector())
# import providers.fitbit.pull  # uncomment when the Fitbit stub is promoted

print("Registered connectors:", list_registered())
connector = get_connector("garmin")
rows = connector.pull_batch(user_id, provider_user_id, date_range)
```

## Rate-limit awareness

The fanout uses a simple sliding-window per provider. If a `pull_batch` call raises `providers.common.connector_protocol.ProviderRateLimitError`, the fanout:
1. Records `status = 'rate_limited'` in `wearable_sync_runs`.
2. Sleeps for the provider's documented cooldown.
3. Retries the user up to N times.
4. Circuit-breaks the provider for the remainder of the run if rate-limiting continues.

## Credentials

Tokens live in Lakebase `wearable_credentials`, envelope-encrypted with the same signing key the AppKit `wearable-core` plugin uses. The notebook reads them via `providers.common.credential_store.LakebaseCredentialStore.from_env()`. Env wiring is in the job parameters — see the notebook.
