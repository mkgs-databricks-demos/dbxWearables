import XCTest
@testable import dbxWearablesApp

final class ActivitySummaryMapperTests: XCTestCase {

    func testActivitySummaryEncodesToNDJSON() throws {
        let summary = ActivitySummary(
            date: "2026-04-14",
            activeEnergyBurnedKcal: 487,
            activeEnergyBurnedGoalKcal: 500,
            exerciseMinutes: 28,
            exerciseMinutesGoal: 30,
            standHours: 9,
            standHoursGoal: 12
        )

        let ndjson = try NDJSONSerializer.encodeToString([summary])
        let lines = ndjson.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)

        let json = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        XCTAssertEqual(json?["date"] as? String, "2026-04-14")
        XCTAssertEqual(json?["active_energy_burned_kcal"] as? Double, 487)
        XCTAssertEqual(json?["stand_hours"] as? Int, 9)
        XCTAssertEqual(json?["stand_hours_goal"] as? Int, 12)
    }
}
