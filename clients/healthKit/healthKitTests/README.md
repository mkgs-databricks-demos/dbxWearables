# healthKitTests — Unit Tests

Unit test suite for the dbxWearables iOS app. Tests cover data models, mappers, serialization, and API communication.

## Test Coverage

| Area | What's Tested |
|---|---|
| **Mappers** | Correct mapping from raw HealthKit objects to Codable models (samples, workouts, sleep sessions, activity summaries) |
| **Serialization** | NDJSON format correctness — one line per record, valid JSON per line, sorted keys, field presence |
| **API Communication** | Request structure, headers (`X-Record-Type`, `X-Device-Id`, etc.), auth token inclusion, error classification (retryable vs. non-retryable), response parsing |
| **Models** | Encoding correctness and payload size for lightweight records (deletions) |

## Subdirectories

| Directory | Description |
|---|---|
| [`Mocks/`](Mocks/) | Mock implementations for isolating units under test |
| [`Models/`](Models/) | Tests for data model encoding and behavior |
| [`Services/`](Services/) | Tests for service-layer logic (API, mappers, serializer) |
