import Foundation

actor Elm327CommandQueue {
    private let transport: ObdTransport

    init(transport: ObdTransport) {
        self.transport = transport
    }

    func execute(_ command: Elm327Command) async throws -> Elm327Response {
        let raw = try await withTimeout(seconds: command.timeout, command: command.command) {
            try await self.transport.send(command.command)
        }
        return try Elm327FrameParser.parse(rawText: raw, command: command)
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        command: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(max(seconds, 0.1) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw Elm327Error.timeout(command: command, seconds: seconds)
            }

            guard let result = try await group.next() else {
                throw Elm327Error.timeout(command: command, seconds: seconds)
            }
            group.cancelAll()
            return result
        }
    }
}
