import Foundation
import Network

/// Monitors network connectivity and provides real-time status updates
@MainActor
final class NetworkMonitor: ObservableObject {
    
    @Published var status: NetworkStatus = .unknown
    @Published var isConnected: Bool = true
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dbxwearables.networkmonitor")
    
    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                let newStatus: NetworkStatus
                let connected: Bool
                
                switch path.status {
                case .satisfied:
                    newStatus = .online
                    connected = true
                case .unsatisfied, .requiresConnection:
                    newStatus = .offline
                    connected = false
                @unknown default:
                    newStatus = .unknown
                    connected = false
                }
                
                // Log network changes
                if newStatus != self.status {
                    if newStatus == .online {
                        print("📡 Network: Connected (\(self.connectionType(path)))")
                    } else {
                        print("📡 Network: Disconnected")
                    }
                }
                
                self.status = newStatus
                self.isConnected = connected
            }
        }
        
        monitor.start(queue: queue)
    }
    
    nonisolated private func stopMonitoring() {
        monitor.cancel()
    }
    
    /// Get a human-readable description of the connection type
    private func connectionType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            return "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        } else {
            return "Unknown"
        }
    }
    
    /// Check if network is available for syncing
    var canSync: Bool {
        isConnected
    }
    
    /// Get appropriate error for current network state
    var networkError: SyncError? {
        status == .offline ? .offline : nil
    }
}
