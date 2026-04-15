import XCTest
@testable import dbxWearablesApp

final class WorkoutMapperTests: XCTestCase {

    func testEmptyInputReturnsEmptyOutput() {
        let result = WorkoutMapper.mapWorkouts([])
        XCTAssertTrue(result.isEmpty)
    }

    func testWorkoutRecordEncodesToNDJSON() throws {
        let record = WorkoutRecord(
            uuid: "W0RKOUT1-0000-0000-0000-000000000000",
            activityType: "running",
            activityTypeRaw: 37,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_002_112),
            durationSeconds: 2112,
            totalEnergyBurnedKcal: 312.5,
            totalDistanceMeters: 4820,
            sourceName: "Apple Watch",
            metadata: nil
        )

        let ndjson = try NDJSONSerializer.encodeToString([record])
        let lines = ndjson.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)

        let json = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        XCTAssertEqual(json?["activity_type"] as? String, "running")
        XCTAssertEqual(json?["activity_type_raw"] as? UInt, 37)
        XCTAssertEqual(json?["duration_seconds"] as? Double, 2112)
        XCTAssertEqual(json?["total_energy_burned_kcal"] as? Double, 312.5)
        XCTAssertEqual(json?["total_distance_meters"] as? Double, 4820)
    }
}
