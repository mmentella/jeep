import Foundation

enum ObdPid: String, CaseIterable, Identifiable {
    case rpm = "010C"
    case speed = "010D"
    case coolantTemperature = "0105"
    case controlModuleVoltage = "0142"
    case engineLoad = "0104"
    case throttlePosition = "0111"

    var id: String { rawValue }
    var command: String { rawValue }

    var title: String {
        switch self {
        case .rpm: return "RPM"
        case .speed: return "Velocita"
        case .coolantTemperature: return "Temp. liquido"
        case .controlModuleVoltage: return "Voltaggio ECU"
        case .engineLoad: return "Carico motore"
        case .throttlePosition: return "Acceleratore"
        }
    }

    var unit: String {
        switch self {
        case .rpm: return "rpm"
        case .speed: return "km/h"
        case .coolantTemperature: return "C"
        case .controlModuleVoltage: return "V"
        case .engineLoad, .throttlePosition: return "%"
        }
    }

    var mode: UInt8 { 0x01 }

    var pidByte: UInt8 {
        UInt8(rawValue.suffix(2), radix: 16) ?? 0
    }

    var displayRange: ClosedRange<Double> {
        switch self {
        case .rpm: return 0...7000
        case .speed: return 0...220
        case .coolantTemperature: return -40...140
        case .controlModuleVoltage: return 0...18
        case .engineLoad, .throttlePosition: return 0...100
        }
    }
}

struct ObdReading: Equatable {
    let pid: ObdPid
    let value: Double
    let rawResponse: String
    let date: Date
}
