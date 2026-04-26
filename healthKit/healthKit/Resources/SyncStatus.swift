import Foundation

/// Detailed sync status for user feedback
enum SyncStatus: Equatable {
    case idle
    case syncing(progress: SyncProgress)
    case retrying(attempt: Int, reason: String)
    case success(summary: SyncSummary)
    case failed(error: SyncError)
    
    var isActive: Bool {
        switch self {
        case .syncing, .retrying: return true
        default: return false
        }
    }
    
    var userMessage: String {
        switch self {
        case .idle:
            return "Ready to sync"
        case .syncing(let progress):
            return progress.message
        case .retrying(let attempt, _):
            return "Retrying (attempt \(attempt))..."
        case .success(let summary):
            return "✓ Synced \(summary.totalRecords) records"
        case .failed(let error):
            return error.userMessage
        }
    }
}

/// Progress information during sync
struct SyncProgress: Equatable {
    let currentType: String
    let completedTypes: Int
    let totalTypes: Int
    let recordsUploaded: Int
    
    var message: String {
        "Syncing \(currentType)... (\(completedTypes)/\(totalTypes) types)"
    }
    
    var percentage: Double {
        guard totalTypes > 0 else { return 0 }
        return Double(completedTypes) / Double(totalTypes)
    }
}

/// Summary of completed sync
struct SyncSummary: Equatable {
    let totalRecords: Int
    let recordsByType: [String: Int]
    let duration: TimeInterval
    let timestamp: Date
    
    var formattedDuration: String {
        String(format: "%.1fs", duration)
    }
}

/// User-friendly sync errors
enum SyncError: Error, Equatable {
    // Network errors
    case offline
    case timeout
    case serverUnavailable(statusCode: Int)
    
    // HealthKit errors
    case healthKitUnauthorized
    case healthKitQueryFailed(dataType: String)
    
    // Data errors
    case serializationFailed
    case invalidData
    
    // Configuration errors
    case endpointNotConfigured
    case authenticationFailed
    
    // Generic
    case unknown(message: String)
    
    var userMessage: String {
        switch self {
        case .offline:
            return "No internet connection. Please check your network."
        case .timeout:
            return "Request timed out. Please try again."
        case .serverUnavailable(let code):
            return "Server error (\(code)). Please try again later."
        case .healthKitUnauthorized:
            return "HealthKit access denied. Check Settings → Health."
        case .healthKitQueryFailed(let dataType):
            return "Failed to read \(dataType) from HealthKit."
        case .serializationFailed:
            return "Failed to prepare data for upload."
        case .invalidData:
            return "Invalid data detected. Please contact support."
        case .endpointNotConfigured:
            return "API endpoint not configured. Check app settings."
        case .authenticationFailed:
            return "Authentication failed. Please sign in again."
        case .unknown(let message):
            return "Error: \(message)"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .serverUnavailable:
            return true
        case .healthKitUnauthorized, .endpointNotConfigured, .authenticationFailed:
            return false
        case .healthKitQueryFailed, .serializationFailed, .invalidData, .unknown:
            return true
        }
    }
    
    var suggestedAction: String? {
        switch self {
        case .offline:
            return "Check WiFi or cellular connection"
        case .timeout:
            return "Try again with better connection"
        case .serverUnavailable:
            return "Wait a few minutes and retry"
        case .healthKitUnauthorized:
            return "Open Settings → Health → Data Access"
        case .healthKitQueryFailed:
            return "Grant HealthKit permissions"
        case .endpointNotConfigured:
            return "Configure API endpoint in settings"
        case .authenticationFailed:
            return "Sign in again"
        default:
            return nil
        }
    }
}

/// Network connectivity status
enum NetworkStatus {
    case online
    case offline
    case unknown
    
    var isReachable: Bool {
        self == .online
    }
}
