import Foundation

enum ObdConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case initializing
    case ready
    case reconnecting
    case disconnected
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .initializing: return "Initializing"
        case .ready: return "Ready"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }
}
