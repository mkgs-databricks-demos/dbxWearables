# Samsung Health (cloud) — intentionally not a connector

Samsung Health **does not expose a cloud API** that a backend connector could talk to. All Samsung Health data stays on-device and is surfaced to Android apps through the Samsung Health SDK (formerly `samsung.health.data` for Galaxy Watch integration).

If you need Samsung Galaxy Watch or Samsung phone health data in `wearables_zerobus`, use the **phone-SDK client pattern**, not the cloud-API connector pattern.

## Where the real implementation lives

See [`clients/samsungHealth/`](../../clients/samsungHealth/) — an Android app placeholder that will use the Samsung Health Data SDK to read the on-device health store, then POST NDJSON to the AppKit gateway at `/api/wearable-core/ingest/samsung_health`.

## Why this stub directory exists at all

To make it explicit for contributors and SAs evaluating the platform: when someone asks "does dbxWearables support Samsung Health?", the answer is yes — via the Android client app, not a server-side connector. This README prevents the reflexive "scaffold me a Samsung connector" mistake.

If Samsung ever ships a cloud API for Samsung Health data, this directory is where that connector would live and it would implement the same `providers.common.connector_protocol.ConnectorProtocol` as every other cloud provider.
