import Foundation

protocol ObdTransport: AnyObject {
    var events: AsyncStream<ObdTransportEvent> { get }
    func startScanning()
    func stopScanning()
    func connect(to peripheralID: UUID) async throws
    func disconnect()
    func send(_ command: String) async throws -> String
}

enum ObdTransportEvent: Equatable {
    case stateChanged(String)
    case discovered(ObdPeripheral)
    case connected(ObdPeripheral)
    case disconnected(String?)
    case log(DiagnosticLogEntry)
}

struct ObdPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum ObdTransportError: LocalizedError {
    case bluetoothUnavailable(String)
    case peripheralNotFound
    case serviceNotFound
    case characteristicNotFound
    case notConnected
    case timeout
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let reason): return "Bluetooth non disponibile: \(reason)"
        case .peripheralNotFound: return "Periferica OBD non trovata"
        case .serviceNotFound: return "Servizio BLE OBD non trovato"
        case .characteristicNotFound: return "Caratteristica BLE OBD non trovata"
        case .notConnected: return "Scanner OBD non connesso"
        case .timeout: return "Timeout in attesa della risposta ELM327"
        case .invalidEncoding: return "Impossibile codificare il comando ELM327"
        }
    }
}
