import XCTest
@testable import dbxWearablesApp

/// `SyncLedger` is the demo's evidence layer: the Payloads tab shows the last
/// NDJSON sent per type, the Dashboard reads cumulative stats from it, and the
/// recent-events feed is bounded to 20 entries. These tests pin down those
/// contracts — the ones a regression would silently break in front of a
/// customer.
///
/// `SyncLedger` always uses `Documents/sync_ledger/` so we wipe that directory
/// between tests to keep them order-independent.
final class SyncLedgerTests: XCTestCase {

    private var ledgerDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("sync_ledger", isDirectory: true)
    }

    override func setUp() async throws {
        try await super.setUp()
        try? FileManager.default.removeItem(at: ledgerDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: ledgerDirectory)
        try await super.tearDown()
    }

    // MARK: - Sample Breakdown

    func testSamplesPayloadParsesTypeIntoBreakdown() async {
        let ledger = SyncLedger()
        let ndjson = """
        {"type":"stepCount","value":1234}
        {"type":"stepCount","value":2345}
        {"type":"heartRate","value":72}
        """

        await ledger.recordSync(
            recordType: "samples",
            recordCount: 3,
            httpStatusCode: 200,
            ndjsonPayload: ndjson,
            requestHeaders: [:]
        )

        let stats = await ledger.getStats()
        XCTAssertEqual(stats.sampleBreakdown["stepCount"], 2)
        XCTAssertEqual(stats.sampleBreakdown["heartRate"], 1)
        XCTAssertEqual(stats.totalRecordsSent["samples"], 3)
    }

    func testSamplesPayloadIgnoresMalformedLines() async {
        let ledger = SyncLedger()
        let ndjson = """
        {"type":"stepCount"}
        not-a-json-line
        {"unrelated":"field"}
        {"type":"distanceWalkingRunning"}
        """

        await ledger.recordSync(
            recordType: "samples",
            recordCount: 4,
            httpStatusCode: 200,
            ndjsonPayload: ndjson,
            requestHeaders: [:]
        )

        let stats = await ledger.getStats()
        XCTAssertEqual(stats.sampleBreakdown["stepCount"], 1)
        XCTAssertEqual(stats.sampleBreakdown["distanceWalkingRunning"], 1)
        XCTAssertEqual(stats.sampleBreakdown.count, 2, "malformed lines must not pollute the breakdown")
    }

    // MARK: - Workouts / Deletes Breakdown

    func testWorkoutsPayloadParsesActivityType() async {
        let ledger = SyncLedger()
        let ndjson = """
        {"activity_type":"running"}
        {"activity_type":"running"}
        {"activity_type":"cycling"}
        """

        await ledger.recordSync(
            recordType: "workouts",
            recordCount: 3,
            httpStatusCode: 200,
            ndjsonPayload: ndjson,
            requestHeaders: [:]
        )

        let stats = await ledger.getStats()
        XCTAssertEqual(stats.workoutBreakdown["running"], 2)
        XCTAssertEqual(stats.workoutBreakdown["cycling"], 1)
    }

    func testDeletesPayloadParsesSampleType() async {
        let ledger = SyncLedger()
        let ndjson = """
        {"sample_type":"stepCount"}
        {"sample_type":"heartRate"}
        """

        await ledger.recordSync(
            recordType: "deletes",
            recordCount: 2,
            httpStatusCode: 200,
            ndjsonPayload: ndjson,
            requestHeaders: [:]
        )

        let stats = await ledger.getStats()
        XCTAssertEqual(stats.deleteBreakdown["stepCount"], 1)
        XCTAssertEqual(stats.deleteBreakdown["heartRate"], 1)
    }

    // MARK: - Aggregate-only record types

    func testSleepIncrementsSessionCountOnly() async {
        let ledger = SyncLedger()
        await ledger.recordSync(
            recordType: "sleep",
            recordCount: 5,
            httpStatusCode: 200,
            ndjsonPayload: "ignored",
            requestHeaders: [:]
        )

        let stats = await ledger.getStats()
        XCTAssertEqual(stats.sleepSessionCount, 5)
        XCTAssertTrue(stats.sampleBreakdown.isEmpty)
    }

    func testActivitySummariesIncrementsDayCountOnly() async {
        let ledger = SyncLedger()
        await ledger.recordSync(
            recordType: "activity_summaries",
            recordCount: 7,
            httpStatusCode: 200,
            ndjsonPayload: "ignored",
            requestHeaders: [:]
        )

        let stats = await ledger.getStats()
        XCTAssertEqual(stats.activitySummaryDayCount, 7)
    }

    // MARK: - Cumulative behaviour

    func testTotalRecordsSentAccumulatesAcrossSyncs() async {
        let ledger = SyncLedger()
        for _ in 0..<3 {
            await ledger.recordSync(
                recordType: "samples",
                recordCount: 10,
                httpStatusCode: 200,
                ndjsonPayload: "{\"type\":\"stepCount\"}",
                requestHeaders: [:]
            )
        }

        let stats = await ledger.getStats()
        XCTAssertEqual(stats.totalRecordsSent["samples"], 30)
    }

    func testLastSyncTimestampUpdatedPerType() async {
        let ledger = SyncLedger()
        let before = Date()

        await ledger.recordSync(
            recordType: "samples",
            recordCount: 1,
            httpStatusCode: 200,
            ndjsonPayload: "{\"type\":\"stepCount\"}",
            requestHeaders: [:]
        )

        let stats = await ledger.getStats()
        guard let stamp = stats.lastSyncTimestamp["samples"] else {
            return XCTFail("lastSyncTimestamp[samples] must be set")
        }
        XCTAssertGreaterThanOrEqual(stamp, before)
    }

    // MARK: - Recent events feed (max 20, payload-stripped)

    func testRecentEventsAreNewestFirst() async {
        let ledger = SyncLedger()
        for i in 0..<3 {
            await ledger.recordSync(
                recordType: "samples",
                recordCount: i,
                httpStatusCode: 200,
                ndjsonPayload: "{\"type\":\"stepCount\"}",
                requestHeaders: [:]
            )
        }

        let events = await ledger.getRecentEvents()
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].recordCount, 2, "newest event must be at index 0")
        XCTAssertEqual(events[2].recordCount, 0, "oldest event must be at the back")
    }

    func testRecentEventsCappedAtTwenty() async {
        let ledger = SyncLedger()
        for i in 0..<25 {
            await ledger.recordSync(
                recordType: "samples",
                recordCount: i,
                httpStatusCode: 200,
                ndjsonPayload: "{\"type\":\"stepCount\"}",
                requestHeaders: [:]
            )
        }

        let events = await ledger.getRecentEvents()
        XCTAssertEqual(events.count, 20)
        // Newest is i=24, oldest retained is i=5 (after dropping 0..<5)
        XCTAssertEqual(events.first?.recordCount, 24)
        XCTAssertEqual(events.last?.recordCount, 5)
    }

    func testRecentEventsStripPayload() async {
        let ledger = SyncLedger()
        await ledger.recordSync(
            recordType: "samples",
            recordCount: 1,
            httpStatusCode: 200,
            ndjsonPayload: "{\"type\":\"stepCount\"}",
            requestHeaders: ["X-Record-Type": "samples"]
        )

        let events = await ledger.getRecentEvents()
        XCTAssertNil(events.first?.ndjsonPayload, "recent events must not retain payloads")
        XCTAssertEqual(events.first?.requestHeaders["X-Record-Type"], "samples", "headers should still be retained")
    }

    // MARK: - Last-payload storage and persistence

    func testLastPayloadStoredAndRetrievablePerType() async {
        let ledger = SyncLedger()
        let samplesPayload = "{\"type\":\"stepCount\"}"
        let workoutsPayload = "{\"activity_type\":\"running\"}"

        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: samplesPayload, requestHeaders: [:])
        await ledger.recordSync(recordType: "workouts", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: workoutsPayload, requestHeaders: [:])

        let samplesRecord = await ledger.getLastPayload(for: "samples")
        let workoutsRecord = await ledger.getLastPayload(for: "workouts")

        XCTAssertEqual(samplesRecord?.ndjsonPayload, samplesPayload)
        XCTAssertEqual(workoutsRecord?.ndjsonPayload, workoutsPayload)
    }

    func testLastPayloadOverwritesPriorPayloadForSameType() async {
        let ledger = SyncLedger()
        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: "{\"type\":\"stepCount\"}",
                                requestHeaders: [:])
        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: "{\"type\":\"heartRate\"}",
                                requestHeaders: [:])

        let last = await ledger.getLastPayload(for: "samples")
        XCTAssertEqual(last?.ndjsonPayload, "{\"type\":\"heartRate\"}",
                       "second sync must overwrite the first for the same record type")
    }

    func testStatsAndEventsSurviveRebuild() async {
        // First instance writes
        do {
            let ledger = SyncLedger()
            await ledger.recordSync(recordType: "samples", recordCount: 4, httpStatusCode: 200,
                                    ndjsonPayload: "{\"type\":\"stepCount\"}",
                                    requestHeaders: [:])
        }

        // Second instance reads from disk on init
        let reborn = SyncLedger()
        let stats = await reborn.getStats()
        let events = await reborn.getRecentEvents()
        XCTAssertEqual(stats.totalRecordsSent["samples"], 4)
        XCTAssertEqual(events.count, 1)
    }

    func testGetLastPayloadReturnsNilWhenAbsent() async {
        let ledger = SyncLedger()
        let result = await ledger.getLastPayload(for: "samples")
        XCTAssertNil(result)
    }
}
