import Foundation

struct PidLabLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let adapterMode: String
    let command: String
    let response: String
    let isStandardRead: Bool
    let warning: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        adapterMode: String,
        command: String,
        response: String,
        isStandardRead: Bool,
        warning: String?
    ) {
        self.id = id
        self.date = date
        self.adapterMode = adapterMode
        self.command = command
        self.response = response
        self.isStandardRead = isStandardRead
        self.warning = warning
    }
}

enum PidLabLogExporter {
    static func jsonData(from entries: [PidLabLogEntry]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(entries)) ?? Data("[]".utf8)
    }

    static func csvString(from entries: [PidLabLogEntry]) -> String {
        let header = ["timestamp", "adapter_mode", "command", "response", "is_standard_read", "warning"].joined(separator: ",")
        let rows = entries.map { entry in
            [
                ISO8601DateFormatter().string(from: entry.date),
                entry.adapterMode,
                entry.command,
                entry.response,
                entry.isStandardRead ? "true" : "false",
                entry.warning ?? ""
            ].map(escapeCsv).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func csvData(from entries: [PidLabLogEntry]) -> Data {
        Data(csvString(from: entries).utf8)
    }

    private static func escapeCsv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
