import Foundation

final class MockObdTransport: ObdTransport {
    private let eventStream: AsyncStream<ObdTransportEvent>
    private let eventContinuation: AsyncStream<ObdTransportEvent>.Continuation
    private var isConnected = false
    private let startedAt = Date()
    private var commandCount = 0

    var events: AsyncStream<ObdTransportEvent> { eventStream }

    init() {
        var continuation: AsyncStream<ObdTransportEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    func startScanning() {
        eventContinuation.yield(.stateChanged("Mock mode attivo"))
        eventContinuation.yield(.discovered(ObdPeripheral(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Mock ELM327 BLE", rssi: -42)))
    }

    func stopScanning() {}

    func connect(to peripheralID: UUID) async throws {
        isConnected = true
        eventContinuation.yield(.connected(ObdPeripheral(id: peripheralID, name: "Mock ELM327 BLE", rssi: -42)))
    }

    func disconnect() {
        isConnected = false
        eventContinuation.yield(.disconnected(nil))
    }

    func send(_ command: String) async throws -> String {
        guard isConnected else { throw ObdTransportError.notConnected }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        commandCount += 1
        eventContinuation.yield(.log(.outgoing(normalized)))
        try await Task.sleep(nanoseconds: UInt64.random(in: 45_000_000...145_000_000))
        let response = mockResponse(for: normalized) + "\r>"
        eventContinuation.yield(.log(.incoming(response)))
        return response
    }

    private func mockResponse(for command: String) -> String {
        switch command {
        case "ATZ": return "ELM327 v1.5"
        case "ATI": return "ELM327 v1.5"
        case "ATRV": return String(format: "%.1fV", controlModuleVoltage)
        case "ATDP": return "AUTO, ISO 15765-4 (CAN 11/500)"
        case "ATDPN": return "A6"
        case "AT@1": return "Mock ELM327"
        case "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0": return "OK"
        case "010C": return response(command: command, bytes: rpmBytes())
        case "010D": return response(command: command, bytes: [UInt8(clamped(speed, min: 0, max: 180))])
        case "0105": return response(command: command, bytes: [UInt8(clamped(coolantTemperature + 40, min: 0, max: 255))])
        case "0142": return response(command: command, bytes: voltageBytes())
        case "0104": return response(command: command, bytes: [percentByte(engineLoad)])
        case "0111": return response(command: command, bytes: [percentByte(throttlePosition)])
        case "0902": return "49 02 01 57 49 4E 4D 4F 43 4B 34 58 45 31 32 33 34 35"
        case let value where value.hasPrefix("22"): return "NO DATA"
        default: return "NO DATA"
        }
    }

    private var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    private var throttlePosition: Double {
        let wave = sin(elapsed * 0.9) * 10 + sin(elapsed * 2.4) * 4
        return clamped(22 + wave + Double(commandCount % 5), min: 6, max: 72)
    }

    private var engineLoad: Double {
        let wave = sin(elapsed * 0.7) * 16 + sin(elapsed * 1.8) * 7
        return clamped(34 + wave + throttlePosition * 0.28, min: 12, max: 88)
    }

    private var rpm: Int {
        let idle = 780.0
        let throttleEffect = throttlePosition * 42
        let wave = sin(elapsed * 1.35) * 220 + sin(elapsed * 0.23) * 120
        return Int(clamped(idle + throttleEffect + wave, min: 720, max: 5200))
    }

    private var speed: Int {
        let cruise = 58 + sin(elapsed * 0.18) * 34 + sin(elapsed * 0.62) * 9
        return Int(clamped(cruise, min: 0, max: 140))
    }

    private var coolantTemperature: Int {
        let warmup = min(elapsed / 180.0, 1.0) * 34
        let oscillation = sin(elapsed * 0.08) * 2.0
        return Int(clamped(58 + warmup + oscillation, min: 45, max: 103))
    }

    private var controlModuleVoltage: Double {
        clamped(13.9 + sin(elapsed * 0.5) * 0.18 + Double.random(in: -0.04...0.04), min: 12.1, max: 14.7)
    }

    private func rpmBytes() -> [UInt8] {
        let encoded = rpm * 4
        return [UInt8((encoded >> 8) & 0xFF), UInt8(encoded & 0xFF)]
    }

    private func voltageBytes() -> [UInt8] {
        let encoded = Int(controlModuleVoltage * 1000)
        return [UInt8((encoded >> 8) & 0xFF), UInt8(encoded & 0xFF)]
    }

    private func percentByte(_ percent: Double) -> UInt8 {
        UInt8(clamped(Int((percent / 100.0) * 255.0), min: 0, max: 255))
    }

    private func response(command: String, bytes: [UInt8]) -> String {
        let pid = command.suffix(2)
        let payload = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "41 \(pid) \(payload)"
    }

    private func clamped(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }

    private func clamped(_ value: Int, min lower: Int, max upper: Int) -> Int {
        Swift.min(Swift.max(value, lower), upper)
    }
}
