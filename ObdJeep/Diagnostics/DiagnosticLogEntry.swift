import Foundation

struct DiagnosticLogEntry: Identifiable, Equatable {
    enum Direction: String {
        case outgoing = "TX"
        case incoming = "RX"
        case info = "INFO"
        case error = "ERR"
    }

    let id = UUID()
    let date: Date
    let direction: Direction
    let message: String

    static func outgoing(_ message: String) -> DiagnosticLogEntry {
        DiagnosticLogEntry(date: Date(), direction: .outgoing, message: message)
    }

    static func incoming(_ message: String) -> DiagnosticLogEntry {
        DiagnosticLogEntry(date: Date(), direction: .incoming, message: message)
    }

    static func info(_ message: String) -> DiagnosticLogEntry {
        DiagnosticLogEntry(date: Date(), direction: .info, message: message)
    }

    static func error(_ message: String) -> DiagnosticLogEntry {
        DiagnosticLogEntry(date: Date(), direction: .error, message: message)
    }
}
