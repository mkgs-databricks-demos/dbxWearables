# Services — Service Layer Tests

Unit tests for the service layer: API communication, data mappers, and serialization.

## Files

| File | Description |
|---|---|
| `APIServiceTests.swift` | Comprehensive tests for `APIService`: success response parsing (200), HTTP error classification (400 non-retryable, 429/500 retryable), request headers (`Content-Type`, `X-Device-Id`, `X-Platform`, `X-App-Version`, `X-Record-Type`), Bearer token authorization, and request structure (endpoint, POST method, NDJSON body). |
| `HealthSampleMapperTests.swift` | Tests that `HealthSampleMapper` correctly maps `HKQuantitySample` objects to `HealthSample` models and handles empty input. |
| `WorkoutMapperTests.swift` | Tests `WorkoutMapper` output: NDJSON encoding, field correctness (activity type, duration, energy, distance), and empty input handling. |
| `SleepMapperTests.swift` | Tests `SleepMapper` session grouping logic and NDJSON encoding with nested sleep stages. |
| `ActivitySummaryMapperTests.swift` | Tests `ActivitySummaryMapper` NDJSON output and field name mapping for Activity Ring values. |
| `NDJSONSerializerTests.swift` | Tests NDJSON format: one line per record, valid JSON per line, sorted keys, empty array produces empty data, and required field presence. |
