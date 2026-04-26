import XCTest
@testable import dbxWearablesApp

/// The Payload Inspector tab is the demo's verification surface — engineers
/// open it on stage to show the exact NDJSON that hit ZeroBus. These tests
/// pin down the parse → preview → pretty-print pipeline and the
/// availableTypes set the tab's selector reads from.
@MainActor
final class PayloadInspectorViewModelTests: XCTestCase {

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

    // MARK: - Empty / missing payload

    func testLoadPayloadWithNoStoredDataYieldsEmptyLines() async {
        let ledger = SyncLedger()
        let sut = PayloadInspectorViewModel(syncLedger: ledger)

        await sut.loadPayload()

        XCTAssertNil(sut.lastPayload)
        XCTAssertTrue(sut.parsedLines.isEmpty)
        XCTAssertTrue(sut.availableTypes.isEmpty)
        XCTAssertFalse(sut.hasPayload(for: "samples"))
    }

    // MARK: - Parsing into lines

    func testEachNDJSONLineBecomesOnePayloadLine() async {
        let ledger = SyncLedger()
        let ndjson = """
        {"type":"stepCount","value":1}
        {"type":"heartRate","value":2}
        {"type":"distanceWalkingRunning","value":3}
        """
        await ledger.recordSync(recordType: "samples", recordCount: 3, httpStatusCode: 200,
                                ndjsonPayload: ndjson, requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        XCTAssertEqual(sut.parsedLines.count, 3)
        XCTAssertEqual(sut.parsedLines.map(\.id), [0, 1, 2], "ids should be the line indices")
    }

    func testTrailingAndEmbeddedBlankLinesAreSkipped() async {
        let ledger = SyncLedger()
        let ndjson = "{\"type\":\"stepCount\"}\n\n{\"type\":\"heartRate\"}\n"
        await ledger.recordSync(recordType: "samples", recordCount: 2, httpStatusCode: 200,
                                ndjsonPayload: ndjson, requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        XCTAssertEqual(sut.parsedLines.count, 2, "blank lines must not become entries")
    }

    // MARK: - Preview truncation

    func testPreviewLeavesShortLinesUntouched() async {
        let ledger = SyncLedger()
        let line = "{\"type\":\"stepCount\"}"
        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: line, requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        XCTAssertEqual(sut.parsedLines.first?.preview, line)
        XCTAssertFalse(sut.parsedLines.first?.preview.hasSuffix("...") ?? true)
    }

    func testPreviewTruncatesAt100CharsWithEllipsis() async {
        let ledger = SyncLedger()
        // Construct a >100-char single JSON line.
        let longValue = String(repeating: "x", count: 200)
        let line = "{\"type\":\"\(longValue)\"}"
        XCTAssertGreaterThan(line.count, 100)

        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: line, requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        guard let preview = sut.parsedLines.first?.preview else {
            return XCTFail("expected a parsed line")
        }
        XCTAssertEqual(preview.count, 103, "100 chars + \"...\" suffix")
        XCTAssertTrue(preview.hasSuffix("..."))
    }

    func testPreviewExactly100CharsIsNotTruncated() async {
        let ledger = SyncLedger()
        // 100-char string of valid-ish JSON (doesn't need to parse for preview)
        let exact = String(repeating: "a", count: 100)
        XCTAssertEqual(exact.count, 100)

        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: exact, requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        XCTAssertEqual(sut.parsedLines.first?.preview, exact, "boundary at 100 must not truncate")
    }

    // MARK: - Pretty-print fullJSON

    func testFullJSONIsPrettyPrintedWithSortedKeys() async {
        let ledger = SyncLedger()
        let line = #"{"type":"stepCount","value":42,"timestamp":"2026-01-01T00:00:00Z"}"#
        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: line, requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        guard let pretty = sut.parsedLines.first?.fullJSON else {
            return XCTFail("expected a parsed line")
        }
        XCTAssertTrue(pretty.contains("\n"), "pretty output should span multiple lines")
        let timestampIdx = pretty.range(of: "timestamp")
        let typeIdx = pretty.range(of: "type")
        let valueIdx = pretty.range(of: "value")
        if let t = timestampIdx, let ty = typeIdx, let v = valueIdx {
            XCTAssertLessThan(t.lowerBound, ty.lowerBound, "keys should be sorted alphabetically")
            XCTAssertLessThan(ty.lowerBound, v.lowerBound)
        } else {
            XCTFail("expected all three keys to appear in pretty output")
        }
    }

    func testFullJSONFallsBackToRawWhenLineIsNotValidJSON() async {
        let ledger = SyncLedger()
        let bogus = "this is not json"
        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: bogus, requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        XCTAssertEqual(sut.parsedLines.first?.fullJSON, bogus,
                       "non-JSON lines must round-trip unchanged through prettyPrint")
    }

    // MARK: - availableTypes / hasPayload

    func testAvailableTypesReflectStoredPayloadsOnly() async {
        let ledger = SyncLedger()
        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: "{\"type\":\"stepCount\"}",
                                requestHeaders: [:])
        await ledger.recordSync(recordType: "workouts", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: "{\"activity_type\":\"running\"}",
                                requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()

        XCTAssertEqual(sut.availableTypes, ["samples", "workouts"])
        XCTAssertTrue(sut.hasPayload(for: "samples"))
        XCTAssertTrue(sut.hasPayload(for: "workouts"))
        XCTAssertFalse(sut.hasPayload(for: "sleep"))
        XCTAssertFalse(sut.hasPayload(for: "deletes"))
    }

    // MARK: - Switching record types

    func testChangingSelectedTypeAndReloadingPicksUpNewPayload() async {
        let ledger = SyncLedger()
        await ledger.recordSync(recordType: "samples", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: "{\"type\":\"stepCount\"}",
                                requestHeaders: [:])
        await ledger.recordSync(recordType: "workouts", recordCount: 1, httpStatusCode: 200,
                                ndjsonPayload: "{\"activity_type\":\"running\"}",
                                requestHeaders: [:])

        let sut = PayloadInspectorViewModel(syncLedger: ledger)
        await sut.loadPayload()
        XCTAssertEqual(sut.lastPayload?.recordType, "samples")

        sut.selectedRecordType = "workouts"
        await sut.loadPayload()
        XCTAssertEqual(sut.lastPayload?.recordType, "workouts")
        XCTAssertTrue(sut.parsedLines.first?.fullJSON.contains("running") ?? false)
    }
}
