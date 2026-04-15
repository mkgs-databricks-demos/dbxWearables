import Foundation

/// A daily activity rings summary, mapped from HKActivitySummary.
struct ActivitySummary: Codable {
    let date: String
    let activeEnergyBurnedKcal: Double
    let activeEnergyBurnedGoalKcal: Double
    let exerciseMinutes: Double
    let exerciseMinutesGoal: Double
    let standHours: Int
    let standHoursGoal: Int

    enum CodingKeys: String, CodingKey {
        case date
        case activeEnergyBurnedKcal = "active_energy_burned_kcal"
        case activeEnergyBurnedGoalKcal = "active_energy_burned_goal_kcal"
        case exerciseMinutes = "exercise_minutes"
        case exerciseMinutesGoal = "exercise_minutes_goal"
        case standHours = "stand_hours"
        case standHoursGoal = "stand_hours_goal"
    }
}
