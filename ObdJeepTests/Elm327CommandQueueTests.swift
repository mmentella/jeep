import XCTest
@testable import ObdJeep

final class Elm327CommandQueueTests: XCTestCase {
    func testSerializesCommands() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)

        async let first = queue.execute(Elm327Command(command: "010C", source: .polling))
        async let second = queue.execute(Elm327Command(command: "010D", source: .manual))

        try await transport.waitForPending(command: "010C")
        XCTAssertTrue(transport.complete(command: "010C", with: "41 0C 0F A0\r>"))
        try await transport.waitForPending(command: "010D")
        XCTAssertTrue(transport.complete(command: "010D", with: "41 0D 2A\r>"))

        _ = try await [first, second]

        XCTAssertEqual(transport.maxInFlight, 1)
        XCTAssertEqual(transport.commands, ["010C", "010D"])
    }

    func testCommandTimeout() async {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)

        do {
            _ = try await queue.execute(Elm327Command(command: "010C", timeout: 0.05, source: .polling))
            XCTFail("Expected timeout")
        } catch let error as Elm327Error {
            if case .timeout(let command, _) = error {
                XCTAssertEqual(command, "010C")
            } else {
                XCTFail("Expected timeout, got \(error)")
            }
        } catch {
            XCTFail("Expected Elm327Error, got \(error)")
        }

        await XCTAssertEventuallyEqual(transport.pendingCount, 0)
    }

    func testDisconnectDuringInFlightCommandFailsCommand() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)
        let task = Task {
            try await queue.execute(Elm327Command(command: "010C", timeout: 1.0, source: .polling))
        }

        try await transport.waitForPending(command: "010C")
        transport.disconnect()

        do {
            _ = try await task.value
            XCTFail("Expected disconnect error")
        } catch ObdTransportError.notConnected {
            XCTAssertEqual(transport.pendingCount, 0)
        } catch {
            XCTFail("Expected notConnected, got \(error)")
        }
    }

    func testDisconnectImmediatelyBeforeResponseWinsOverLateResponse() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)
        let task = Task {
            try await queue.execute(Elm327Command(command: "010C", timeout: 1.0, source: .polling))
        }

        try await transport.waitForPending(command: "010C")
        transport.disconnect()
        XCTAssertFalse(transport.complete(command: "010C", with: "41 0C 0F A0\r>"))

        do {
            _ = try await task.value
            XCTFail("Expected disconnect error")
        } catch ObdTransportError.notConnected {
            XCTAssertEqual(transport.pendingCount, 0)
        } catch {
            XCTFail("Expected notConnected, got \(error)")
        }
    }

    func testDisconnectImmediatelyAfterResponseDoesNotCancelCompletedCommand() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)
        let task = Task {
            try await queue.execute(Elm327Command(command: "010C", timeout: 1.0, source: .polling))
        }

        try await transport.waitForPending(command: "010C")
        XCTAssertTrue(transport.complete(command: "010C", with: "41 0C 0F A0\r>"))
        transport.disconnect()

        let response = try await task.value
        XCTAssertEqual(response.normalizedText, "41 0C 0F A0")
        XCTAssertEqual(transport.pendingCount, 0)
    }

    func testLateResponseAfterTimeoutIsIgnoredAndNextCommandCanRun() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)

        do {
            _ = try await queue.execute(Elm327Command(command: "010C", timeout: 0.05, source: .polling))
            XCTFail("Expected timeout")
        } catch let error as Elm327Error {
            guard case .timeout = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        }

        await XCTAssertEventuallyEqual(transport.pendingCount, 0)
        XCTAssertFalse(transport.complete(command: "010C", with: "41 0C 0F A0\r>"))

        let nextTask = Task {
            try await queue.execute(Elm327Command(command: "010D", timeout: 1.0, source: .manual))
        }
        try await transport.waitForPending(command: "010D")
        XCTAssertTrue(transport.complete(command: "010D", with: "41 0D 2A\r>"))
        _ = try await nextTask.value
    }

    func testTwoConcurrentCommandsRemainSerialized() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)

        let firstTask = Task {
            try await queue.execute(Elm327Command(command: "010C", timeout: 1.0, source: .manual))
        }
        let secondTask = Task {
            try await queue.execute(Elm327Command(command: "010D", timeout: 1.0, source: .manual))
        }

        try await transport.waitForPending(command: "010C")
        XCTAssertEqual(transport.pendingCount, 1)
        XCTAssertTrue(transport.complete(command: "010C", with: "41 0C 0F A0\r>"))
        try await transport.waitForPending(command: "010D")
        XCTAssertEqual(transport.pendingCount, 1)
        XCTAssertTrue(transport.complete(command: "010D", with: "41 0D 2A\r>"))

        _ = try await [firstTask.value, secondTask.value]
        XCTAssertEqual(transport.maxInFlight, 1)
    }

    func testPollingReadAndPidLabCommandRemainSerialized() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)
        let client = Elm327Client(queue: queue)

        async let polling = client.read(.rpm)
        async let manual = client.sendManualReadCommand("010D")

        try await transport.waitForPending(command: "010C")
        XCTAssertTrue(transport.complete(command: "010C", with: "41 0C 0F A0\r>"))
        try await transport.waitForPending(command: "010D")
        XCTAssertTrue(transport.complete(command: "010D", with: "41 0D 2A\r>"))

        _ = try await (polling, manual)
        XCTAssertEqual(transport.maxInFlight, 1)
        XCTAssertEqual(transport.commands, ["010C", "010D"])
    }

    func testTaskCancellationDuringResponseWaitReleasesQueue() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)
        let task = Task {
            try await queue.execute(Elm327Command(command: "010C", timeout: 1.0, source: .manual))
        }

        try await transport.waitForPending(command: "010C")
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            await XCTAssertEventuallyEqual(transport.pendingCount, 0)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let nextTask = Task {
            try await queue.execute(Elm327Command(command: "010D", timeout: 1.0, source: .manual))
        }
        try await transport.waitForPending(command: "010D")
        XCTAssertTrue(transport.complete(command: "010D", with: "41 0D 2A\r>"))
        _ = try await nextTask.value
    }

    func testTimeoutFollowedByReconnectAllowsNewCommand() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)

        do {
            _ = try await queue.execute(Elm327Command(command: "010C", timeout: 0.05, source: .manual))
            XCTFail("Expected timeout")
        } catch let error as Elm327Error {
            guard case .timeout = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        }

        transport.disconnect()
        try await transport.connect(to: UUID())

        let task = Task {
            try await queue.execute(Elm327Command(command: "010D", timeout: 1.0, source: .manual))
        }
        try await transport.waitForPending(command: "010D")
        XCTAssertTrue(transport.complete(command: "010D", with: "41 0D 2A\r>"))
        _ = try await task.value
    }

    func testMultipleRapidDisconnectReconnectCyclesDoNotLeavePendingCommands() async throws {
        let transport = ControlledTransport()
        let queue = Elm327CommandQueue(transport: transport)

        for _ in 0..<5 {
            let task = Task {
                try await queue.execute(Elm327Command(command: "010C", timeout: 1.0, source: .manual))
            }

            try await transport.waitForPending(command: "010C")
            transport.disconnect()

            do {
                _ = try await task.value
                XCTFail("Expected disconnect error")
            } catch ObdTransportError.notConnected {
                XCTAssertEqual(transport.pendingCount, 0)
            } catch {
                XCTFail("Expected notConnected, got \(error)")
            }

            try await transport.connect(to: UUID())
        }

        let finalTask = Task {
            try await queue.execute(Elm327Command(command: "010D", timeout: 1.0, source: .manual))
        }
        try await transport.waitForPending(command: "010D")
        XCTAssertTrue(transport.complete(command: "010D", with: "41 0D 2A\r>"))
        _ = try await finalTask.value
    }
}

private final class ControlledTransport: ObdTransport {
    private struct Pending {
        let id: UUID
        let command: String
        let continuation: CheckedContinuation<String, Error>
    }

    private let lock = NSLock()
    private var isConnected = true
    private var active = 0
    private var storedCommands: [String] = []
    private var storedMaxInFlight = 0
    private var pending: [Pending] = []

    let events = AsyncStream<ObdTransportEvent> { _ in }

    var commands: [String] {
        lock.withLock { storedCommands }
    }

    var maxInFlight: Int {
        lock.withLock { storedMaxInFlight }
    }

    var pendingCount: Int {
        lock.withLock { pending.count }
    }

    func startScanning() {}
    func stopScanning() {}

    func connect(to peripheralID: UUID) async throws {
        lock.withLock {
            isConnected = true
        }
    }

    func disconnect() {
        let continuations: [CheckedContinuation<String, Error>] = lock.withLock {
            isConnected = false
            active = 0
            let continuations = pending.map(\.continuation)
            pending.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume(throwing: ObdTransportError.notConnected) }
    }

    func send(_ command: String) async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldReject = lock.withLock { () -> Bool in
                    guard isConnected else { return true }
                    active += 1
                    storedMaxInFlight = max(storedMaxInFlight, active)
                    storedCommands.append(command)
                    pending.append(Pending(id: id, command: command, continuation: continuation))
                    return false
                }
                if shouldReject {
                    continuation.resume(throwing: ObdTransportError.notConnected)
                }
            }
        } onCancel: {
            _ = self.complete(id: id, with: .failure(CancellationError()))
        }
    }

    func complete(command: String, with response: String) -> Bool {
        complete(where: { $0.command == command }, with: .success(response))
    }

    func waitForPending(command: String, timeoutNanoseconds: UInt64 = 500_000_000) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        while Date() < deadline {
            if lock.withLock({ pending.contains(where: { $0.command == command }) }) {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for pending command \(command)")
    }

    private func complete(id: UUID, with result: Result<String, Error>) -> Bool {
        complete(where: { $0.id == id }, with: result)
    }

    private func complete(where predicate: (Pending) -> Bool, with result: Result<String, Error>) -> Bool {
        let continuation: CheckedContinuation<String, Error>? = lock.withLock {
            guard let index = pending.firstIndex(where: predicate) else { return nil }
            active = max(active - 1, 0)
            return pending.remove(at: index).continuation
        }
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}

private func XCTAssertEventuallyEqual<T: Equatable>(
    _ expression: @autoclosure () -> T,
    _ expected: T,
    timeoutNanoseconds: UInt64 = 500_000_000,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
    while Date() < deadline {
        if expression() == expected {
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertEqual(expression(), expected, file: file, line: line)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
