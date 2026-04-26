import XCTest
@testable import dbxWearablesApp

/// Locks down the user-facing copy and retry-eligibility logic exposed by
/// `SyncStatus`, `SyncError`, `SyncProgress`, and `NetworkStatus`. The
/// dashboard's `SyncStatusCard` reads these computed properties directly,
/// so a typo or a wrongly-classified retryable error would silently ship.
final class SyncStatusTests: XCTestCase {

    // MARK: - SyncStatus.isActive

    func testIsActiveTrueOnlyWhileSyncing() {
        let progress = SyncProgress(currentType: "steps", completedTypes: 1, totalTypes: 5, recordsUploaded: 10)
        XCTAssertTrue(SyncStatus.syncing(progress: progress).isActive)
        XCTAssertTrue(SyncStatus.retrying(attempt: 2, reason: "transient").isActive)

        XCTAssertFalse(SyncStatus.idle.isActive)
        XCTAssertFalse(SyncStatus.success(summary: .init(totalRecords: 0, recordsByType: [:], duration: 0, timestamp: .init())).isActive)
        XCTAssertFalse(SyncStatus.failed(error: .offline).isActive)
    }

    // MARK: - SyncStatus.userMessage

    func testIdleMessage() {
        XCTAssertEqual(SyncStatus.idle.userMessage, "Ready to sync")
    }

    func testSyncingMessageDelegatesToProgress() {
        let progress = SyncProgress(currentType: "heartRate", completedTypes: 2, totalTypes: 5, recordsUploaded: 0)
        XCTAssertEqual(SyncStatus.syncing(progress: progress).userMessage, progress.message)
    }

    func testRetryingMessageIncludesAttempt() {
        let message = SyncStatus.retrying(attempt: 3, reason: "5xx").userMessage
        XCTAssertTrue(message.contains("3"), "attempt count should appear in user message: \(message)")
    }

    func testSuccessMessageIncludesRecordCount() {
        let summary = SyncSummary(totalRecords: 42, recordsByType: ["steps": 42], duration: 1.234, timestamp: Date())
        XCTAssertEqual(SyncStatus.success(summary: summary).userMessage, "✓ Synced 42 records")
    }

    func testFailureMessageDelegatesToError() {
        XCTAssertEqual(SyncStatus.failed(error: .offline).userMessage, SyncError.offline.userMessage)
    }

    // MARK: - SyncProgress

    func testProgressMessageContainsTypeAndCount() {
        let progress = SyncProgress(currentType: "steps", completedTypes: 2, totalTypes: 5, recordsUploaded: 100)
        XCTAssertEqual(progress.message, "Syncing steps... (2/5 types)")
    }

    func testPercentageHandlesZeroTotalTypes() {
        let progress = SyncProgress(currentType: "", completedTypes: 0, totalTypes: 0, recordsUploaded: 0)
        XCTAssertEqual(progress.percentage, 0, "must not divide by zero")
    }

    func testPercentageHalfwayThrough() {
        let progress = SyncProgress(currentType: "x", completedTypes: 2, totalTypes: 4, recordsUploaded: 0)
        XCTAssertEqual(progress.percentage, 0.5)
    }

    // MARK: - SyncSummary

    func testSummaryFormatsDurationToOneDecimal() {
        let summary = SyncSummary(totalRecords: 1, recordsByType: [:], duration: 2.456, timestamp: Date())
        XCTAssertEqual(summary.formattedDuration, "2.5s")
    }

    // MARK: - SyncError.userMessage

    func testEveryErrorCaseProducesNonEmptyMessage() {
        let cases: [SyncError] = [
            .offline,
            .timeout,
            .serverUnavailable(statusCode: 503),
            .healthKitUnauthorized,
            .healthKitQueryFailed(dataType: "steps"),
            .serializationFailed,
            .invalidData,
            .endpointNotConfigured,
            .authenticationFailed,
            .unknown(message: "boom")
        ]
        for error in cases {
            XCTAssertFalse(error.userMessage.isEmpty, "userMessage must be set for \(error)")
        }
    }

    func testServerUnavailableMessageIncludesStatusCode() {
        XCTAssertTrue(SyncError.serverUnavailable(statusCode: 503).userMessage.contains("503"))
    }

    func testHealthKitQueryFailedMessageIncludesDataType() {
        XCTAssertTrue(SyncError.healthKitQueryFailed(dataType: "heartRate").userMessage.contains("heartRate"))
    }

    func testUnknownMessageIncludesUnderlyingDetail() {
        XCTAssertTrue(SyncError.unknown(message: "spline reticulation").userMessage.contains("spline reticulation"))
    }

    // MARK: - SyncError.isRetryable

    /// Anything network-shaped or transient should retry; anything that
    /// requires the user to fix something (perms / config / creds) should not.
    func testRetryableErrorsRetry() {
        XCTAssertTrue(SyncError.offline.isRetryable)
        XCTAssertTrue(SyncError.timeout.isRetryable)
        XCTAssertTrue(SyncError.serverUnavailable(statusCode: 500).isRetryable)
        XCTAssertTrue(SyncError.healthKitQueryFailed(dataType: "steps").isRetryable)
        XCTAssertTrue(SyncError.serializationFailed.isRetryable)
        XCTAssertTrue(SyncError.invalidData.isRetryable)
        XCTAssertTrue(SyncError.unknown(message: "x").isRetryable)
    }

    func testNonRetryableErrorsDoNotRetry() {
        XCTAssertFalse(SyncError.healthKitUnauthorized.isRetryable)
        XCTAssertFalse(SyncError.endpointNotConfigured.isRetryable)
        XCTAssertFalse(SyncError.authenticationFailed.isRetryable)
    }

    // MARK: - SyncError.suggestedAction

    func testSuggestedActionPresentForActionableErrors() {
        XCTAssertNotNil(SyncError.offline.suggestedAction)
        XCTAssertNotNil(SyncError.timeout.suggestedAction)
        XCTAssertNotNil(SyncError.serverUnavailable(statusCode: 500).suggestedAction)
        XCTAssertNotNil(SyncError.healthKitUnauthorized.suggestedAction)
        XCTAssertNotNil(SyncError.healthKitQueryFailed(dataType: "x").suggestedAction)
        XCTAssertNotNil(SyncError.endpointNotConfigured.suggestedAction)
        XCTAssertNotNil(SyncError.authenticationFailed.suggestedAction)
    }

    func testSuggestedActionNilForGenericErrors() {
        XCTAssertNil(SyncError.serializationFailed.suggestedAction)
        XCTAssertNil(SyncError.invalidData.suggestedAction)
        XCTAssertNil(SyncError.unknown(message: "x").suggestedAction)
    }

    // MARK: - NetworkStatus

    func testIsReachableTrueOnlyWhenOnline() {
        XCTAssertTrue(NetworkStatus.online.isReachable)
        XCTAssertFalse(NetworkStatus.offline.isReachable)
        XCTAssertFalse(NetworkStatus.unknown.isReachable)
    }
}
