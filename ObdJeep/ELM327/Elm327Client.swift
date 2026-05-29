import Foundation

final class Elm327Client {
    private let transport: ObdTransport

    init(transport: ObdTransport) {
        self.transport = transport
    }

    func initialize() async throws {
        _ = try await transport.send("ATZ")
        try await Task.sleep(nanoseconds: 800_000_000)
        for command in ["ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"] {
            _ = try await transport.send(command)
        }
    }

    func read(_ pid: ObdPid) async throws -> ObdReading {
        let raw = try await transport.send(pid.command)
        let value = try ObdValueParser.parse(rawResponse: raw, pid: pid)
        return ObdReading(pid: pid, value: value, rawResponse: raw, date: Date())
    }

    func sendRawReadCommand(_ command: String) async throws -> String {
        try await transport.send(ObdCommandPolicy.normalize(command))
    }
}
