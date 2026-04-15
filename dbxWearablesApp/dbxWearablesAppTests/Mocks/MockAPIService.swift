import Foundation
@testable import dbxWearablesApp

/// Mock API service for unit testing the sync coordinator without network calls.
final class MockAPIService {

    var postResult: Result<APIResponse, Error> = .success(
        APIResponse(status: "ok", message: "Ingested", recordId: "mock-record-id")
    )

    /// Records each call as (recordType, recordCount) for assertions.
    var postedCalls: [(recordType: String, count: Int)] = []

    func postRecords<T: Encodable>(_ records: [T], recordType: String) async throws -> APIResponse {
        postedCalls.append((recordType, records.count))
        return try postResult.get()
    }
}
