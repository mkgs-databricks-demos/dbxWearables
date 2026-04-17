# Strava connector (stub)

Cloud-API connector for [Strava](https://developers.strava.com/). Not yet implemented.

> **Note on scope:** Strava is activity-centric (workouts, segments, routes) rather than health-centric. It complements — doesn't replace — a vitals-oriented connector like Garmin or Whoop. Use it when the demo needs rich workout detail (routes, power/cadence, segments) alongside the vitals other providers contribute.

## What this connector will provide

- **Auth:** OAuth 2.0 (Authorization Code). Scopes: `read activity:read activity:read_all`.
- **Webhook:** Strava Subscriptions API — registers at app level (not per-user); receive `create/update/delete` events for activities and athletes.
- **Poll:** REST API (`/athlete/activities`, `/activities/{id}`, `/activities/{id}/streams`).

## What you need to implement

1. **AppKit plugin** at [`app/plugins/strava/`](../../app/plugins/strava/README.md):
   - Scaffold via `npx @databricks/appkit plugin create --path app/plugins/strava --name strava`.
   - Manifest resources (optional): `clientId`, `clientSecret`, `webhookVerifyToken`.
   - Implement `StravaConnector extends BaseOAuth2Connector`.
2. **Pull connector** at `providers/strava/pull/`:
   - `pull_batch(user_id, provider_user_id, range)` pages `/athlete/activities` since the anchor.
   - For each activity, optionally fetch `/activities/{id}/streams` to get time-series (heart rate, cadence, power, lat/lng).
3. **Silver normalizer** at `providers/strava/silver/normalizer.py`:
   - Suggested `metric_type`: `workout_duration`, `workout_distance`, `workout_calories`, `workout_avg_hr`, `workout_max_hr`, `workout_avg_power`, `workout_elevation_gain`.

## Record types

- `strava_activity_summary`
- `strava_activity_streams` (large — gate behind a flag per user)
- `strava_athlete_profile`

## References

- [Strava Developer](https://developers.strava.com/)
- [Strava Webhook docs](https://developers.strava.com/docs/webhooks/)
- Contract: [`providers/common/connector_protocol.py`](../common/connector_protocol.py)
