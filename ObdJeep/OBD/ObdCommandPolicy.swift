import Foundation

enum ObdCommandPolicy {
    enum Decision: Equatable {
        case allowStandard
        case warnNonStandard(String)
        case block(String)
    }

    static func evaluate(_ rawCommand: String) -> Decision {
        let command = normalize(rawCommand)
        guard !command.isEmpty else {
            return .block("Inserisci un comando OBD/ELM327.")
        }
        guard command.range(of: #"^[A-Z0-9 @\.]+$"#, options: .regularExpression) != nil else {
            return .block("Sono ammessi solo caratteri ASCII per comandi OBD/ELM327.")
        }

        if command.hasPrefix("AT") {
            return allowedElmCommand(command) ? .allowStandard : .block("Comando AT non consentito nel PID Lab.")
        }

        guard command.count.isMultiple(of: 2), command.range(of: #"^[0-9A-F]+$"#, options: .regularExpression) != nil else {
            return .block("Usa byte esadecimali completi, ad esempio 010C o 22F190.")
        }

        let service = String(command.prefix(2))
        if blockedServices.contains(service) {
            return .block("Servizio \(service) bloccato: il PID Lab non invia scritture, reset, security access o codifica centralina.")
        }
        if standardReadServices.contains(service) {
            return .allowStandard
        }
        if service == "22" {
            return .warnNonStandard("Il servizio 22 e usato spesso per dati proprietari. Invia solo se sei certo che sia una lettura e che il veicolo sia in condizioni sicure.")
        }
        if readLikeServices.contains(service) {
            return .warnNonStandard("Comando non standard per questa app. Verifica che sia solo lettura prima di inviarlo.")
        }
        return .block("Servizio \(service) non permesso: sono ammessi solo comandi di lettura.")
    }

    static func normalize(_ rawCommand: String) -> String {
        rawCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static let standardReadServices: Set<String> = ["01", "02", "03", "07", "09", "0A"]
    private static let readLikeServices: Set<String> = ["18", "19", "22"]
    private static let blockedServices: Set<String> = [
        "04", "10", "11", "14", "27", "28", "2E", "2F", "31", "34", "35", "36", "37", "3B", "85"
    ]

    private static func allowedElmCommand(_ command: String) -> Bool {
        let allowedExact: Set<String> = ["ATZ", "ATI", "ATRV", "ATDP", "ATDPN", "AT@1", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"]
        return allowedExact.contains(command)
    }
}
