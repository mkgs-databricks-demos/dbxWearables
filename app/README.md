# AppKit Gateway — dbxWearables

This is the single Databricks AppKit application that serves as the **Health Data Gateway** for every dbxWearables source:

- Cloud-API connector webhooks (Garmin, Fitbit, Whoop, Oura, Withings, Strava)
- Phone-SDK client POSTs (iOS HealthKit, Android Health Connect, Samsung Health)
- OAuth consent flows (Garmin and every other cloud provider)
- The React Connections UI where users link / unlink their wearables

Built on [Databricks AppKit](https://databricks.github.io/appkit/docs/).

## Status

The AppKit codebase is bootstrapped via `databricks apps init`. The plugin **skeletons** under [`plugins/`](plugins/) are pre-authored for the wearables domain and are meant to be imported into the app scaffold AppKit generates. See [`SETUP.md`](SETUP.md) for the merge procedure.

Three tiers of plugins:

| Tier | Plugin | Concern |
| --- | --- | --- |
| 1 | [`zerobus/`](plugins/zerobus/) | Generic ZeroBus SDK writer (no row-shape opinion) — candidate for upstream contribution |
| 2 | [`wearable-core/`](plugins/wearable-core/) | Platform: Lakebase schema, credential store, bronze row shape, OAuth base classes, connector registry |
| 3 | `garmin/`, `fitbit/`, ... | One per wearable vendor — OAuth routes + webhook handler + connector registration |

## Layout

```
app/
  README.md                  this file
  SETUP.md                   how to merge skeletons with `databricks apps init` output
  plugins/
    zerobus/                 Tier 1 — generic ZeroBus SDK plugin
    wearable-core/           Tier 2 — platform plugin (migrations, credential store, bronze writer, registry)
    garmin/                  Tier 3 — full reference connector
    fitbit/                  Tier 3 — stub (manifest + README)
    whoop/                   Tier 3 — stub
    oura/                    Tier 3 — stub
    withings/                Tier 3 — stub
    strava/                  Tier 3 — stub

  (after databricks apps init runs, also:)
  app.yaml                   Databricks Apps manifest (postgres + sql-warehouse resources)
  package.json, tsconfig.json, etc.
  server/server.ts           createApp({ plugins: [server(), lakebase(), analytics(), caching(), zerobus(), wearableCore(), garmin(), fitbit(), ...] })
  client/                    React UI (Vite)
    ui/Connections.tsx
```
