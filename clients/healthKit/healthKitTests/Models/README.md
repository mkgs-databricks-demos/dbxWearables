# Models — Model Tests

Unit tests for data model encoding and behavior.

## Files

| File | Description |
|---|---|
| `DeletionRecordTests.swift` | Tests that `DeletionRecord` encodes correctly to NDJSON and produces a lightweight payload (under 200 bytes per record). Verifies that only UUID and sample type fields are included — no unnecessary data. |
