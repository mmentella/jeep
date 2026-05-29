import Foundation

enum Elm327Error: LocalizedError, Equatable {
    case noData(raw: String)
    case stopped(raw: String)
    case searching(raw: String)
    case busError(raw: String)
    case canError(raw: String)
    case unableToConnect(raw: String)
    case negativeResponse(service: String?, code: String?, raw: String)
    case malformedFrame(raw: String)
    case unexpectedResponse(expected: String, raw: String)
    case timeout(command: String, seconds: TimeInterval)
    case adapterError(message: String, raw: String)

    var errorDescription: String? {
        switch self {
        case .noData: return "ELM327: NO DATA"
        case .stopped: return "ELM327: STOPPED"
        case .searching: return "ELM327: SEARCHING senza risposta finale"
        case .busError: return "ELM327: BUS ERROR"
        case .canError: return "ELM327: CAN ERROR"
        case .unableToConnect: return "ELM327: UNABLE TO CONNECT"
        case .negativeResponse(let service, let code, _):
            return "ECU negative response service=\(service ?? "?") code=\(code ?? "?")"
        case .malformedFrame: return "ELM327: frame malformato"
        case .unexpectedResponse(let expected, _): return "Risposta inattesa, prefisso atteso \(expected)"
        case .timeout(let command, let seconds): return "Timeout \(command) dopo \(String(format: "%.1f", seconds))s"
        case .adapterError(let message, _): return "ELM327: \(message)"
        }
    }
}
