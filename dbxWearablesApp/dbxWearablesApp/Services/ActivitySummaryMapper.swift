import Foundation
import HealthKit

/// Maps HKActivitySummary objects into Codable ActivitySummary models.
enum ActivitySummaryMapper {

    static func map(_ summary: HKActivitySummary) -> ActivitySummary {
        let calendar = Calendar.current
        let dateString = DateFormatters.dateOnly.string(
            from: calendar.date(from: summary.dateComponents(for: calendar))!
        )

        return ActivitySummary(
            date: dateString,
            activeEnergyBurnedKcal: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
            activeEnergyBurnedGoalKcal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
            exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
            exerciseMinutesGoal: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
            standHours: Int(summary.appleStandHours.doubleValue(for: .count())),
            standHoursGoal: Int(summary.appleStandHoursGoal.doubleValue(for: .count()))
        )
    }

    static func mapSummaries(_ summaries: [HKActivitySummary]) -> [ActivitySummary] {
        summaries.map(map)
    }
}
