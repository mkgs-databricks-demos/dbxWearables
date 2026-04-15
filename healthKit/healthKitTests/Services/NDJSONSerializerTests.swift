import XCTest
@testable import dbxWearablesApp

final class NDJSONSerializerTests: XCTestCase {

    func testEncodeProducesOneLinePerRecord() throws {
        let samples = [
            HealthSample(
                uuid: "A1B2C3D4-0001-0000-0000-000000000000",
                type: "HKQuantityTypeIdentifierStepCount",
                value: 1243,
                unit: "count",
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                sourceName: "Apple Watch",
                sourceBundleId: "com.apple.health",
                metadata: nil
            ),
            HealthSample(
                uuid: "A1B2C3D4-0002-0000-0000-000000000000",
                type: "HKQuantityTypeIdentifierHeartRate",
                value: 72,
                unit: "count/min",
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_000_000),
                sourceName: "Apple Watch",
                sourceBundleId: "com.apple.health",
                metadata: ["HKMetadataKeyHeartRateMotionContext": "1"]
            ),
        ]

        let ndjson = try NDJSONSerializer.encodeToString(samples)
        let lines = ndjson.split(separator: "\n")

        XCTAssertEqual(lines.count, 2, "NDJSON should have one line per sample")

        // Each line should be valid JSON on its own
        for line in lines {
            let data = Data(line.utf8)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    func testEncodeEmptyArrayProducesEmptyData() throws {
        let data = try NDJSONSerializer.encode([HealthSample]())
        XCTAssertTrue(data.isEmpty)
    }

    func testEachLineContainsExpectedFields() throws {
        let sample = HealthSample(
            uuid: "A1B2C3D4-0003-0000-0000-000000000000",
            type: "HKQuantityTypeIdentifierStepCount",
            value: 500,
            unit: "count",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            sourceName: "Apple Watch",
            sourceBundleId: nil,
            metadata: nil
        )

        let ndjson = try NDJSONSerializer.encodeToString([sample])
        let line = ndjson.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "HKQuantityTypeIdentifierStepCount")
        XCTAssertEqual(json?["value"] as? Double, 500)
        XCTAssertEqual(json?["unit"] as? String, "count")
        XCTAssertEqual(json?["source_name"] as? String, "Apple Watch")
        XCTAssertNotNil(json?["start_date"])
        XCTAssertNotNil(json?["end_date"])
    }
}
