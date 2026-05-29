import Foundation

struct Elm327Frame: Equatable {
    let header: String?
    let bytes: [UInt8]
    let line: String
}

struct Elm327Response: Equatable {
    let command: Elm327Command
    let rawText: String
    let normalizedText: String
    let lines: [String]
    let frames: [Elm327Frame]
    let promptSeen: Bool
    let isOK: Bool
}

enum Elm327FrameParser {
    static func parse(rawText: String, command: Elm327Command) throws -> Elm327Response {
        let promptSeen = rawText.contains(">")
        let normalized = normalize(rawText)
        let lines = normalized
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { $0.components(separatedBy: "\r") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != ">" && $0 != command.command }

        if normalized.contains("UNABLE TO CONNECT") {
            throw Elm327Error.unableToConnect(raw: rawText)
        }
        if normalized.contains("BUS ERROR") || normalized.contains("BUS INIT: ERROR") {
            throw Elm327Error.busError(raw: rawText)
        }
        if normalized.contains("CAN ERROR") {
            throw Elm327Error.canError(raw: rawText)
        }
        if normalized.contains("BUFFER FULL") || normalized.contains("RX ERROR") {
            throw Elm327Error.adapterError(message: "BUFFER/RX ERROR", raw: rawText)
        }
        if normalized.contains("STOPPED") {
            throw Elm327Error.stopped(raw: rawText)
        }
        if normalized.contains("NO DATA") {
            throw Elm327Error.noData(raw: rawText)
        }
        if lines.allSatisfy({ $0 == "SEARCHING..." }) {
            throw Elm327Error.searching(raw: rawText)
        }
        if normalized.contains("?") {
            throw Elm327Error.adapterError(message: "Comando non riconosciuto", raw: rawText)
        }

        var frames: [Elm327Frame] = []
        var sawSearching = false
        for line in lines {
            if line == "SEARCHING..." {
                sawSearching = true
                continue
            }
            if line == "OK" || line.hasPrefix("ELM327") || line.hasSuffix("V") || line.contains("ISO ") || line.hasPrefix("AUTO,") {
                continue
            }
            let frame = try parseFrameLine(line, rawText: rawText)
            for index in 0..<(max(frame.bytes.count - 2, 0)) {
                if frame.bytes[index] == 0x7F {
                    throw Elm327Error.negativeResponse(
                        service: String(format: "%02X", frame.bytes[index + 1]),
                        code: String(format: "%02X", frame.bytes[index + 2]),
                        raw: rawText
                    )
                }
            }
            frames.append(frame)
        }

        if sawSearching, frames.isEmpty, !lines.contains("OK") {
            throw Elm327Error.searching(raw: rawText)
        }

        if let expected = command.expectedResponsePrefix {
            let hasExpected = normalized
                .replacingOccurrences(of: " ", with: "")
                .contains(expected.replacingOccurrences(of: " ", with: ""))
            if !hasExpected {
                throw Elm327Error.unexpectedResponse(expected: expected, raw: rawText)
            }
        }

        if frames.isEmpty && !lines.contains("OK") && !lines.contains(where: { $0.hasPrefix("ELM327") || $0.hasSuffix("V") || $0.contains("ISO ") || $0.hasPrefix("AUTO,") }) {
            throw Elm327Error.malformedFrame(raw: rawText)
        }

        return Elm327Response(
            command: command,
            rawText: rawText,
            normalizedText: normalized,
            lines: lines,
            frames: frames,
            promptSeen: promptSeen,
            isOK: lines.contains("OK")
        )
    }

    static func normalize(_ rawText: String) -> String {
        rawText
            .uppercased()
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseFrameLine(_ line: String, rawText: String) throws -> Elm327Frame {
        let tokens = line.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            throw Elm327Error.malformedFrame(raw: rawText)
        }

        if tokens.count == 1 {
            let bytes = try parseCompactHex(tokens[0], rawText: rawText)
            return Elm327Frame(header: nil, bytes: bytes, line: line)
        }

        var header: String?
        var bytes: [UInt8] = []
        for token in tokens {
            if token.count == 3, UInt16(token, radix: 16) != nil, header == nil {
                header = token
                continue
            }
            if token.count == 2, let byte = UInt8(token, radix: 16) {
                bytes.append(byte)
                continue
            }
            if token.count > 2, token.count.isMultiple(of: 2) {
                bytes.append(contentsOf: try parseCompactHex(token, rawText: rawText))
                continue
            }
            throw Elm327Error.malformedFrame(raw: rawText)
        }
        guard !bytes.isEmpty else {
            throw Elm327Error.malformedFrame(raw: rawText)
        }
        return Elm327Frame(header: header, bytes: bytes, line: line)
    }

    private static func parseCompactHex(_ compact: String, rawText: String) throws -> [UInt8] {
        guard compact.count >= 2, compact.count.isMultiple(of: 2) else {
            throw Elm327Error.malformedFrame(raw: rawText)
        }
        let bytes = stride(from: 0, to: compact.count, by: 2).compactMap { index -> UInt8? in
            let start = compact.index(compact.startIndex, offsetBy: index)
            let end = compact.index(start, offsetBy: 2)
            return UInt8(compact[start..<end], radix: 16)
        }
        guard bytes.count * 2 == compact.count else {
            throw Elm327Error.malformedFrame(raw: rawText)
        }
        return bytes
    }
}
