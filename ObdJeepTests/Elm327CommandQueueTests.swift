import XCTest
@testable import ObdJeep

final class Elm327CommandQueueTests: XCTestCase {
    func testSerializesCommands() async throws {
        let transport = QueueTestTransport(delayNanoseconds: 120_000_000)
        let queue = Elm327CommandQueue(transport: transport)

        async let first = queue.execute(Elm327Command(command: "010C", source: .polling))
        async let second = queue.execute(Elm327Command(command: "010D", source: .manual))

        _ = try await [first, second]

        XCTAssertEqual(transport.maxInFlight, 1)
        XCTAssertEqual(transport.commands, ["010C", "010D"])
    }

    func testCommandTimeout() async {
        let transport = QueueTestTransport(delayNanoseconds: 500_000_000)
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
    }
}

private final class QueueTestTransport: ObdTransport {
    private let lock = NSLock()
    private let delayNanoseconds: UInt64
    private var active = 0
    private var storedCommands: [String] = []
    private var storedMaxInFlight = 0

    let events = AsyncStream<ObdTransportEvent> { _ in }

    var commands: [String] {
        lock.withLock { storedCommands }
    }

    var maxInFlight: Int {
        lock.withLock { storedMaxInFlight }
    }

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func startScanning() {}
    func stopScanning() {}
    func connect(to peripheralID: UUID) async throws {}
    func disconnect() {}

    func send(_ command: String) async throws -> String {
        lock.withLock {
            active += 1
            storedMaxInFlight = max(storedMaxInFlight, active)
            storedCommands.append(command)
        }
        defer {
            lock.withLock {
                active -= 1
            }
        }
        try await Task.sleep(nanoseconds: delayNanoseconds)
        switch command {
        case "010C": return "41 0C 0F A0\r>"
        case "010D": return "41 0D 2A\r>"
        default: return "OK\r>"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
