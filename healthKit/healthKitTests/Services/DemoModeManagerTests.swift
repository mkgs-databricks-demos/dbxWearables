import XCTest
@testable import dbxWearablesApp

/// Unit tests for `DemoModeManager` schedule management and the
/// `checkScheduledDeletions(using:)` deleter-injection path. The closure
/// overload lets us cover the deletion semantics without touching HealthKit.
@MainActor
final class DemoModeManagerTests: XCTestCase {

    private let scheduleKey = "scheduledDeletions"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: scheduleKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: scheduleKey)
        super.tearDown()
    }

    // MARK: - Schedule management

    func testScheduleHealthKitDeletionAppendsAndPersists() {
        let manager = DemoModeManager()
        XCTAssertTrue(manager.scheduledDeletions.isEmpty)

        manager.scheduleHealthKitDeletion(recordCount: 42, dataTypes: ["steps", "heartRate"])

        XCTAssertEqual(manager.scheduledDeletions.count, 1)
        let stored = manager.scheduledDeletions[0]
        XCTAssertEqual(stored.recordCount, 42)
        XCTAssertEqual(stored.dataTypes, ["steps", "heartRate"])
        XCTAssertGreaterThan(stored.timeRemaining, 3590, "Should be ~3600s away (1 hour)")

        // Persisted to UserDefaults
        XCTAssertNotNil(UserDefaults.standard.data(forKey: scheduleKey))
    }

    func testCancelScheduledDeletionRemovesById() {
        let manager = DemoModeManager()
        manager.scheduleHealthKitDeletion(recordCount: 10, dataTypes: ["steps"])
        manager.scheduleHealthKitDeletion(recordCount: 20, dataTypes: ["heartRate"])
        XCTAssertEqual(manager.scheduledDeletions.count, 2)

        let toCancel = manager.scheduledDeletions[0]
        manager.cancelScheduledDeletion(toCancel)

        XCTAssertEqual(manager.scheduledDeletions.count, 1)
        XCTAssertEqual(manager.scheduledDeletions[0].recordCount, 20)
    }

    // MARK: - checkScheduledDeletions(using:)

    func testCheckScheduledDeletionsNoopWhenNoneExpired() async {
        let manager = DemoModeManager()
        manager.scheduleHealthKitDeletion(recordCount: 5, dataTypes: ["steps"]) // 1 hour out
        let countBefore = manager.scheduledDeletions.count

        var deleterCallCount = 0
        await manager.checkScheduledDeletions(using: {
            deleterCallCount += 1
        })

        XCTAssertEqual(deleterCallCount, 0, "Deleter must not run when nothing is expired")
        XCTAssertEqual(manager.scheduledDeletions.count, countBefore, "Schedules untouched")
    }

    func testCheckScheduledDeletionsCallsDeleterOnceAndClearsAll() async {
        let manager = DemoModeManager()
        seedSchedules(on: manager, expired: [
            (records: 10, dataTypes: ["steps"]),
            (records: 20, dataTypes: ["heartRate"]),
        ], future: [
            (records: 5, dataTypes: ["sleep"]),
        ])
        XCTAssertEqual(manager.scheduledDeletions.count, 3)

        var deleterCallCount = 0
        await manager.checkScheduledDeletions(using: {
            deleterCallCount += 1
        })

        XCTAssertEqual(deleterCallCount, 1,
                       "Bulk metadata delete should fire exactly once even with multiple expired schedules")
        XCTAssertTrue(manager.scheduledDeletions.isEmpty,
                      "All schedules cleared because the bulk delete wipes future schedules' data too")
        XCTAssertEqual(loadPersistedSchedules().count, 0, "Cleared list must be persisted")
    }

    func testCheckScheduledDeletionsKeepsSchedulesWhenDeleterThrows() async {
        let manager = DemoModeManager()
        seedSchedules(on: manager, expired: [
            (records: 10, dataTypes: ["steps"]),
        ], future: [])
        let countBefore = manager.scheduledDeletions.count

        struct DeleterError: Error {}
        await manager.checkScheduledDeletions(using: {
            throw DeleterError()
        })

        XCTAssertEqual(manager.scheduledDeletions.count, countBefore,
                       "Failed deletion must leave schedules in place so a retry can pick them up")
    }

    // MARK: - load filter (carry over across launches)

    func testLoadKeepsFutureAndRecentlyExpiredButDropsOldExpired() {
        // Seed UserDefaults directly with a mix and then construct a manager
        // to trigger loadScheduledDeletions().
        let now = Date()
        let payload: [DemoModeManager.ScheduledDeletion] = [
            .init(id: UUID(), scheduledFor: now.addingTimeInterval(1800),  recordCount: 1, dataTypes: ["future"]),
            .init(id: UUID(), scheduledFor: now.addingTimeInterval(-1800), recordCount: 2, dataTypes: ["recent_expired"]),
            .init(id: UUID(), scheduledFor: now.addingTimeInterval(-7200), recordCount: 3, dataTypes: ["old_expired"]),
        ]
        UserDefaults.standard.set(try! JSONEncoder().encode(payload), forKey: scheduleKey)

        let manager = DemoModeManager()

        let kept = manager.scheduledDeletions.map { $0.dataTypes.first ?? "" }.sorted()
        XCTAssertEqual(kept, ["future", "recent_expired"],
                       "Should drop schedules expired more than 1 hour ago")
    }

    // MARK: - Helpers

    private func seedSchedules(
        on manager: DemoModeManager,
        expired: [(records: Int, dataTypes: [String])],
        future: [(records: Int, dataTypes: [String])]
    ) {
        // scheduleHealthKitDeletion always sets +1h, so we have to bypass it
        // by setting `scheduledDeletions` directly via the published array.
        let now = Date()
        var records: [DemoModeManager.ScheduledDeletion] = []
        for entry in expired {
            records.append(.init(
                id: UUID(),
                scheduledFor: now.addingTimeInterval(-60),
                recordCount: entry.records,
                dataTypes: entry.dataTypes
            ))
        }
        for entry in future {
            records.append(.init(
                id: UUID(),
                scheduledFor: now.addingTimeInterval(3600),
                recordCount: entry.records,
                dataTypes: entry.dataTypes
            ))
        }
        manager.scheduledDeletions = records
    }

    private func loadPersistedSchedules() -> [DemoModeManager.ScheduledDeletion] {
        guard let data = UserDefaults.standard.data(forKey: scheduleKey) else { return [] }
        return (try? JSONDecoder().decode([DemoModeManager.ScheduledDeletion].self, from: data)) ?? []
    }
}
