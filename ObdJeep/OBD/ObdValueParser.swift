import Foundation

enum ObdParsingError: LocalizedError, Equatable {
    case noData(String)
    case negativeResponse(String)
    case malformedResponse(String)
    case pidMismatch(expected: ObdPid, raw: String)
    case insufficientBytes(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .noData(let raw): return "Nessun dato disponibile: \(raw)"
        case .negativeResponse(let raw): return "Risposta negativa ECU: \(raw)"
        case .malformedResponse(let raw): return "Risposta ELM327 non valida: \(raw)"
        case .pidMismatch(let expected, let raw): return "Risposta non coerente con \(expected.command): \(raw)"
        case .insufficientBytes(let expected, let actual): return "Byte insufficienti: attesi \(expected), ricevuti \(actual)"
        }
    }
}

enum ObdValueParser {
    static func parse(rawResponse: String, pid: ObdPid) throws -> Double {
        let bytes = try payloadBytes(from: rawResponse, pid: pid)
        switch pid {
        case .rpm:
            try require(bytes, count: 2)
            return Double(Int(bytes[0]) * 256 + Int(bytes[1])) / 4.0
        case .speed:
            try require(bytes, count: 1)
            return Double(bytes[0])
        case .coolantTemperature:
            try require(bytes, count: 1)
            return Double(Int(bytes[0]) - 40)
        case .controlModuleVoltage:
            try require(bytes, count: 2)
            return Double(Int(bytes[0]) * 256 + Int(bytes[1])) / 1000.0
        case .engineLoad, .throttlePosition:
            try require(bytes, count: 1)
            return Double(bytes[0]) * 100.0 / 255.0
        }
    }

    private static func payloadBytes(from rawResponse: String, pid: ObdPid) throws -> [UInt8] {
        let normalized = rawResponse
            .uppercased()
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ">", with: " ")
            .replacingOccurrences(of: "SEARCHING...", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("NO DATA") || normalized.isEmpty {
            throw ObdParsingError.noData(rawResponse)
        }
        if normalized.contains("7F") || normalized.contains("UNABLE TO CONNECT") || normalized.contains("STOPPED") || normalized.contains("?") {
            throw ObdParsingError.negativeResponse(rawResponse)
        }

        let compact = normalized
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .joined()
        guard compact.count >= 4, compact.count.isMultiple(of: 2) else {
            throw ObdParsingError.malformedResponse(rawResponse)
        }

        let bytes = stride(from: 0, to: compact.count, by: 2).compactMap { index -> UInt8? in
            let start = compact.index(compact.startIndex, offsetBy: index)
            let end = compact.index(start, offsetBy: 2)
            return UInt8(compact[start..<end], radix: 16)
        }

        guard bytes.count * 2 == compact.count else {
            throw ObdParsingError.malformedResponse(rawResponse)
        }

        let expectedMode = pid.mode + 0x40
        for index in 0..<(bytes.count - 1) {
            if bytes[index] == expectedMode, bytes[index + 1] == pid.pidByte {
                return Array(bytes.dropFirst(index + 2))
            }
        }

        throw ObdParsingError.pidMismatch(expected: pid, raw: rawResponse)
    }

    private static func require(_ bytes: [UInt8], count: Int) throws {
        guard bytes.count >= count else {
            throw ObdParsingError.insufficientBytes(expected: count, actual: bytes.count)
        }
    }
}
