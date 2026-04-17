# dbxWearables

**A Databricks-native platform for ingesting and analyzing data from any consumer wearable or health app.**

Built on [Databricks AppKit](https://databricks.github.io/appkit/), [ZeroBus](https://docs.databricks.com/aws/en/ingestion/zerobus-overview/), [Spark Declarative Pipelines](https://docs.databricks.com/aws/en/delta-live-tables/), [Lakebase](https://docs.databricks.com/aws/en/oltp/), and AI/BI.

The design target: a customer can onboard **any consumer wearable** — Garmin, Fitbit, Whoop, Oura, Withings, Strava, Apple Watch, Samsung Galaxy Watch, any Android-paired wearable — into Databricks through a single gateway app and one shared bronze table. Adding a new provider is a plugin, not a fork.

---

## Architecture at a glance

```
Wearable device
  │
  ├── paired with phone ──► iOS / Android / Samsung app ──► POST NDJSON ──┐
  │                                                                         │
  └── paired with vendor cloud ──► Garmin / Fitbit / Whoop / Oura / ... ──┐ │
                                          │                                 │ │
                                          webhook or pull                   ▼ ▼
                                                              ┌────────────────────────┐
                                                              │ Databricks AppKit app  │
                                                              │  (Node.js + TS)        │
                                                              │                        │
                                                              │  plugins:              │
                                                              │   • server             │
                                                              │   • lakebase ──────────┼──► Lakebase (identity, credentials, anchors)
                                                              │   • analytics          │
                                                              │   • caching            │
                                                              │   • zerobus            │
                                                              │   • wearable-core      │
                                                              │   • garmin, fitbit, …  │
                                                              └───────────┬────────────┘
                                                                          │ ZeroBus SDK
                                                                          ▼
                                                           ┌──────────────────────────────┐
                                                           │ wearables_zerobus (VARIANT)  │
                                                           └───────────────┬──────────────┘
                                                                           │
                                                                           ▼
                                                           ┌──────────────────────────────┐
                                                           │ Spark Declarative Pipeline   │
                                                           │ ─► silver_health_events      │
                                                           │ ─► gold_* per use case       │
                                                           └──────────────────────────────┘
```

Every source — no matter how data arrived — lands in the same bronze row shape:

```
{ record_id, ingested_at, body: VARIANT, headers: VARIANT, record_type: STRING }
```

Silver dispatches on `headers:"X-Platform"` to a small per-provider normalizer and projects everything into a single `HealthEvent` row (`source, user_id, device_id, metric_type, value, unit, recorded_at, metadata`). Gold pipelines never see vendor differences.

---

## Two integration patterns

| Pattern | Use when | Where code lives |
| --- | --- | --- |
| **Cloud-API connector plugin** | Vendor exposes OAuth + webhooks or polling (Garmin, Fitbit, Whoop, Oura, Withings, Strava) | [`app/plugins/<provider>/`](app/plugins/) + [`providers/<name>/`](providers/) |
| **Phone-SDK client app** | Vendor health store is on-device only (HealthKit, Health Connect, Samsung Health) | [`clients/<name>/`](clients/) — Swift / Kotlin app POSTs to `/api/wearable-core/ingest/:platform` |

Both patterns produce the same bronze shape. The AppKit app is the only piece that needs to know the difference.

---

## Capability matrix

| Provider | Pattern | Auth | Webhook | Poll | Status |
| --- | --- | --- | --- | --- | --- |
| Garmin | Cloud-API connector plugin | OAuth 1.0a (Health API) | PING→PULL | python-garminconnect / garth (dev) | **Full reference impl** |
| Fitbit | Cloud-API connector plugin | OAuth 2.0 + PKCE | Subscription API | Web API | Stub — see `providers/fitbit/` |
| Whoop | Cloud-API connector plugin | OAuth 2.0 | v2 webhooks | REST | Stub |
| Oura | Cloud-API connector plugin | OAuth 2.0 + PKCE | v2 webhooks | REST | Stub |
| Withings | Cloud-API connector plugin | OAuth 2.0 | Notify API | REST | Stub |
| Strava | Cloud-API connector plugin | OAuth 2.0 | Subscriptions | REST | Stub (activity-centric) |
| Apple Watch / iPhone | Phone-SDK client | Apple ID (on device) | — | — | **Client app built** at [`clients/healthKit/`](clients/healthKit/) |
| Android Wear / phone | Phone-SDK client | Android account | — | — | Placeholder at [`clients/androidHealthConnect/`](clients/androidHealthConnect/) |
| Galaxy Watch / Samsung phone | Phone-SDK client | Samsung account | — | — | Placeholder at [`clients/samsungHealth/`](clients/samsungHealth/) |

---

## Repository layout

```
dbxWearables/
  app/                                   AppKit gateway (see app/SETUP.md)
    plugins/
      zerobus/                           Tier 1 — generic ZeroBus writer (candidate for upstream contribution)
      wearable-core/                     Tier 2 — migrations, credential store, bronze writer, connector registry
      garmin/                            Tier 3 — full reference connector
      fitbit/ whoop/ oura/ withings/ strava/    Tier 3 — stubs

  providers/                             Backend connector code (pull + silver + notebooks)
    common/
      silver/health_event.py             Canonical silver schema
      connector_protocol.py              Python mirror of WearableConnector
      credential_store.py                LakebaseCredentialStore
    garmin/                              Full impl: pull + Connect IQ watch widget + silver + notebooks
    fitbit/ whoop/ oura/ withings/ strava/    Contributor-guide stubs
    samsung_health_cloud/                Explicit "no cloud API — use clients/samsungHealth"

  clients/                               Mobile / watch client apps
    healthKit/                           iOS + Apple Watch — built
    androidHealthConnect/                Android placeholder
    samsungHealth/                       Samsung placeholder

  lakeflow/                              Shared fan-out jobs across providers
    wearable_daily_fanout.ipynb
    wearable_backfill_fanout.ipynb

  zeroBus/
    dbxW_zerobus_infra/                  DABs bundle: schema, secret scope, SPN, warehouse, bronze table

  README.md  ·  CLAUDE.md
```

---

## Answering the common questions

### "Do we still need direct vendor integrations if the phone already syncs to Apple Health / Google Health Connect?"

Yes, for fidelity. Apple Health strips HRV summaries, sleep stages, Body Battery, VO2 max; Google Health Connect and Samsung Health each drop different fields; and phone-sync is polled (which is why your cycling computer takes 15+ minutes to show up in Apple Health). Phone-sync is the easiest onboarding path — install the app, grant read permission — so the platform offers it as the default. Customers who need full data fidelity link the vendor cloud directly via a connector plugin; vendor webhooks bypass the phone entirely.

### "Why ZeroBus instead of writing directly to Delta from a Spark Declarative Pipeline?"

For a pull-only demo, there's no material difference — an SDP streaming read of a notebook-written table works fine. The advantage surfaces once both push and pull sources coexist (which this platform always does). ZeroBus gives every producer (phone POST, Garmin webhook, Fitbit subscription, Whoop webhook, Lakeflow polling) the same wire format with SDK-managed retries and OTel. Silver code stays single-shape per provider rather than per-provider-per-path. The `wearable-core` `bronzeWriter` layers the canonical `{record_id, ingested_at, body, headers, record_type}` shape on top of a generic `AppKit.zerobus.writeRow(...)`, and the direct-Delta path is retained as a degraded fallback (see `providers/garmin/notebooks/03_ingest_garmin_direct.ipynb`) for environments where the ZeroBus SPN isn't yet provisioned.

### "What credential model does the platform use?"

Three tiers, same plumbing:

1. **Single-user dev** — `providers/garmin/scripts/upload_garmin_tokens.sh` writes tokens directly to Lakebase under a synthetic `_dev` user. Good for demos.
2. **Small multi-user** — admin bulk-loads tokens via the same CLI wrapper. Still OAuth tokens per user, still in Lakebase.
3. **Enterprise / production** — each cloud provider's official Developer Program OAuth flow (Garmin 1.0a, everyone else OAuth 2.0 PKCE). Users click "Connect" in the React Connections UI, go through vendor consent, and the AppKit app persists envelope-encrypted tokens in Lakebase. Encryption key is pluggable (Lakebase-resident default; Vault / AWS Secrets Manager / Azure Key Vault supported via the `CredentialStore` interface).

---

## Getting started

Full sequence is in [`app/SETUP.md`](app/SETUP.md). Abbreviated:

```bash
# 1. Shared infra (schema, secret scope, SPN, bronze table, SQL warehouse)
cd zeroBus/dbxW_zerobus_infra
databricks bundle deploy --target dev
databricks bundle run wearables_uc_setup --target dev

# 2. AppKit gateway (one-time scaffold, merging the pre-authored plugin skeletons)
cd ../../
databricks apps init  # target: app/, pick server/lakebase/analytics/caching plugins
cd app && databricks apps deploy

# 3. Link a user to Garmin via the Connections UI (or run the dev fallback)
./providers/garmin/scripts/upload_garmin_tokens.sh --profile <your-profile>

# 4. Deploy the Lakeflow fanout jobs
cd ../lakeflow && databricks bundle deploy --target dev   # job bundle created with the first provider
```

---

## Documentation

- [`app/README.md`](app/README.md) — AppKit gateway overview
- [`app/SETUP.md`](app/SETUP.md) — How to merge the pre-authored plugin skeletons with `databricks apps init`
- [`app/plugins/zerobus/README.md`](app/plugins/zerobus/README.md) — Tier-1 ZeroBus plugin
- [`app/plugins/wearable-core/README.md`](app/plugins/wearable-core/README.md) — Tier-2 platform plugin
- [`app/plugins/garmin/README.md`](app/plugins/garmin/README.md) — Tier-3 reference connector
- [`providers/garmin/README.md`](providers/garmin/README.md) — Garmin domain-side (pull + Connect IQ widget + silver)
- [`providers/common/connector_protocol.py`](providers/common/connector_protocol.py) — Python contract for pull implementations
- [`zeroBus/dbxW_zerobus_infra/README.md`](zeroBus/dbxW_zerobus_infra/README.md) — Shared infrastructure bundle
- [`lakeflow/README.md`](lakeflow/README.md) — Fan-out job architecture

## License

MIT. See [LICENSE](LICENSE).
