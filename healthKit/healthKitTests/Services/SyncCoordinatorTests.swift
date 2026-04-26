import XCTest
import HealthKit
@testable import dbxWearablesApp

/// Unit-test version of the device smoke flow: open app → tap "Sync Now" →
/// see a success summary. We can't drive HealthKit auth from a test bundle, so
/// the queries return zero records — but the SyncCoordinator state machine
/// should still transition .idle → .syncing → .success(SyncSummary), and the
/// dashboard's success card reads directly from those published fields.
@MainActor
final class SyncCoordinatorTests: XCTestCase {

    private var sut: SyncCoordinator!
    private var mockAuth: MockAuthService!

    override func setUp() async throws {
        try await super.setUp()

        // APIConfiguration.baseURL fatalErrors when this is missing.
        setenv("DBX_API_BASE_URL", "https://test.databricks.com/apps/wearables", 1)

        // Any POST that does happen returns 200 OK so the pipeline can finish.
        let okBody = #"{"status":"ok","message":"Ingested","record_id":"mock-id"}"#
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(okBody.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockAuth = MockAuthService(token: "test-token")
        let apiService = APIService(
            session: URLSession(configuration: config),
            auth: mockAuth
        )

        sut = SyncCoordinator(
            healthStore: HKHealthStore(),
            apiService: apiService,
            syncStateRepository: SyncStateRepository(),
            syncLedger: SyncLedger()
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockAuth = nil
        MockURLProtocol.requestHandler = nil
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        XCTAssertEqual(sut.syncStatus, .idle)
        XCTAssertFalse(sut.isSyncing)
        XCTAssertNil(sut.lastSyncDate)
        XCTAssertEqual(sut.lastSyncRecordCount, 0)
    }

    // MARK: - Smoke Flow (Happy Path)

    func testSyncNowProducesSuccessSummary() async {
        await sut.sync(context: .foreground)

        XCTAssertFalse(sut.isSyncing, "isSyncing should clear once sync completes")
        XCTAssertNotNil(sut.lastSyncDate, "lastSyncDate should be stamped on completion")

        guard case .success(let summary) = sut.syncStatus else {
            return XCTFail("Expected syncStatus to be .success(summary), got \(sut.syncStatus)")
        }
        XCTAssertEqual(summary.totalRecords, sut.lastSyncRecordCount)
        XCTAssertGreaterThanOrEqual(summary.duration, 0)
    }
}
