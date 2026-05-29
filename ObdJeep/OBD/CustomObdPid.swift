import Foundation

struct CustomObdPid: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let request: String
    let expectedResponsePrefix: String
    let formula: String
    let unit: String
    let category: ObdPidCategory
}

enum ObdPidCategory: String, CaseIterable, Codable, Identifiable {
    case standard
    case jeep
    case hybrid
    case battery
    case charging
    case twelveVoltBattery
    case dcDcConverter
    case hvBattery
    case chargingStatus
    case hybridSystem
    case dtc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .jeep: return "Jeep"
        case .hybrid: return "Hybrid"
        case .battery: return "Battery"
        case .charging: return "Charging"
        case .twelveVoltBattery: return "12V Battery"
        case .dcDcConverter: return "DC/DC Converter"
        case .hvBattery: return "HV Battery"
        case .chargingStatus: return "Charging Status"
        case .hybridSystem: return "Hybrid System"
        case .dtc: return "DTC"
        }
    }
}

enum CustomPidCatalog {
    static let placeholders: [CustomObdPid] = [
        CustomObdPid(
            id: "jeep-4xe-12v-placeholder",
            name: "Jeep 4xe 12V battery placeholder",
            request: "",
            expectedResponsePrefix: "",
            formula: "",
            unit: "V",
            category: .twelveVoltBattery
        ),
        CustomObdPid(
            id: "jeep-4xe-dcdc-placeholder",
            name: "Jeep 4xe DC/DC converter placeholder",
            request: "",
            expectedResponsePrefix: "",
            formula: "",
            unit: "V",
            category: .dcDcConverter
        ),
        CustomObdPid(
            id: "jeep-4xe-hv-battery-placeholder",
            name: "Jeep 4xe HV battery placeholder",
            request: "",
            expectedResponsePrefix: "",
            formula: "",
            unit: "%",
            category: .hvBattery
        ),
        CustomObdPid(
            id: "jeep-4xe-charging-status-placeholder",
            name: "Jeep 4xe charging status placeholder",
            request: "",
            expectedResponsePrefix: "",
            formula: "",
            unit: "",
            category: .chargingStatus
        ),
        CustomObdPid(
            id: "jeep-4xe-hybrid-system-placeholder",
            name: "Jeep 4xe hybrid system placeholder",
            request: "",
            expectedResponsePrefix: "",
            formula: "",
            unit: "",
            category: .hybridSystem
        ),
        CustomObdPid(
            id: "jeep-4xe-dtc-placeholder",
            name: "Jeep 4xe DTC placeholder",
            request: "",
            expectedResponsePrefix: "",
            formula: "",
            unit: "",
            category: .dtc
        )
    ]
}
