# Mocks — Test Doubles

Mock implementations used to isolate units under test from external dependencies.

## Files

| File | Description |
|---|---|
| `MockAPIService.swift` | A mock API service that records call history (method, URL, headers, body) without making network requests. Used by `SyncCoordinator` tests to verify correct API interactions — request count, headers sent, and payload content. |
