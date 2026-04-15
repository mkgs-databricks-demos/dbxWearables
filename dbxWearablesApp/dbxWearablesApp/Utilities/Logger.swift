import OSLog

/// Unified logging for the app, wrapping Apple's os.Logger.
enum Log {
    static let healthKit = Logger(subsystem: "com.dbxwearables", category: "HealthKit")
    static let api = Logger(subsystem: "com.dbxwearables", category: "API")
    static let sync = Logger(subsystem: "com.dbxwearables", category: "Sync")
}
