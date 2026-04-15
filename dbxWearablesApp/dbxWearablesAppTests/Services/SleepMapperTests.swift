import XCTest
@testable import dbxWearablesApp

final class SleepMapperTests: XCTestCase {

    // SleepMapper.mapSleepSamples expects [HKSample] which can't be constructed
    // outside HealthKit. These tests validate the mapper handles empty input
    // and that the model structs are correctly formed.

    func testEmptyInputReturnsEmptyOutput() {
        let result = SleepMapper.mapSleepSamples([])
        XCTAssertTrue(result.isEmpty)
    }

    func testSleepRecordEncodesToJSON() throws {
        let record = SleepRecord(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_028_000),
            stages: [
                SleepStage(uuid: "SLP00001-0000-0000-0000-000000000000", stage: "asleepCore", startDate: Date(timeIntervalSince1970: 1_700_001_000), endDate: Date(timeIntervalSince1970: 1_700_010_000)),
                SleepStage(uuid: "SLP00002-0000-0000-0000-000000000000", stage: "asleepDeep", startDate: Date(timeIntervalSince1970: 1_700_010_000), endDate: Date(timeIntervalSince1970: 1_700_018_000)),
                SleepStage(uuid: "SLP00003-0000-0000-0000-000000000000", stage: "asleepREM", startDate: Date(timeIntervalSince1970: 1_700_018_000), endDate: Date(timeIntervalSince1970: 1_700_025_000)),
            ]
        )

        let ndjson = try NDJSONSerializer.encodeToString([record])
        let lines = ndjson.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, "One sleep record should produce one NDJSON line")

        let json = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        let stages = json?["stages"] as? [[String: Any]]
        XCTAssertEqual(stages?.count, 3)
        XCTAssertEqual(stages?[0]["stage"] as? String, "asleepCore")
    }
}
