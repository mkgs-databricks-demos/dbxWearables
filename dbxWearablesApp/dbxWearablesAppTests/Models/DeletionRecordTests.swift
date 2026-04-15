import XCTest
@testable import dbxWearablesApp

final class DeletionRecordTests: XCTestCase {

    func testDeletionRecordEncodesToNDJSON() throws {
        let deletions = [
            DeletionRecord(uuid: "A1B2C3D4-0001-0000-0000-000000000000", sampleType: "HKQuantityTypeIdentifierHeartRate"),
            DeletionRecord(uuid: "A1B2C3D4-0002-0000-0000-000000000000", sampleType: "HKQuantityTypeIdentifierStepCount"),
        ]

        let ndjson = try NDJSONSerializer.encodeToString(deletions)
        let lines = ndjson.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)

        let json = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        XCTAssertEqual(json?["uuid"] as? String, "A1B2C3D4-0001-0000-0000-000000000000")
        XCTAssertEqual(json?["sample_type"] as? String, "HKQuantityTypeIdentifierHeartRate")
    }

    func testDeletionRecordIsLightweight() throws {
        let deletion = DeletionRecord(uuid: "A1B2C3D4-0001-0000-0000-000000000000", sampleType: "HKQuantityTypeIdentifierHeartRate")
        let data = try NDJSONSerializer.encode([deletion])

        // A deletion record should be well under 200 bytes
        XCTAssertLessThan(data.count, 200)
    }
}
