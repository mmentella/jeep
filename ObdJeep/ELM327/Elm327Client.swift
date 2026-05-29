import Foundation

final class Elm327Client {
    private let queue: Elm327CommandQueue

    init(queue: Elm327CommandQueue) {
        self.queue = queue
    }

    func initialize() async throws {
        _ = try await queue.execute(Elm327Command(command: "ATZ", timeout: 5.0, source: .initialization))
        try await Task.sleep(nanoseconds: 800_000_000)
        for command in ["ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"] {
            _ = try await queue.execute(Elm327Command(command: command, timeout: 2.0, expectedResponsePrefix: "OK", source: .initialization))
        }
    }

    func read(_ pid: ObdPid) async throws -> ObdReading {
        let expected = String(format: "41%02X", pid.pidByte)
        let response = try await queue.execute(Elm327Command(
            command: pid.command,
            timeout: 3.0,
            expectedResponsePrefix: expected,
            source: .polling
        ))
        let value = try ObdValueParser.parse(rawResponse: response.normalizedText, pid: pid)
        return ObdReading(pid: pid, value: value, rawResponse: response.rawText, date: Date())
    }

    func sendManualReadCommand(_ command: String) async throws -> Elm327Response {
        try await queue.execute(Elm327Command(command: command, timeout: 5.0, source: .manual))
    }
}
