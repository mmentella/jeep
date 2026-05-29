import Foundation
import SwiftUI

@MainActor
final class ObdDashboardViewModel: ObservableObject {
    enum AdapterMode: String, CaseIterable, Identifiable {
        case mock
        case liveBluetooth

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mock: return "Mock Adapter"
            case .liveBluetooth: return "Live Bluetooth"
            }
        }
    }

    typealias TransportFactory = (AdapterMode) -> ObdTransport

    @Published var adapterMode: AdapterMode = .mock
    @Published var isConnected = false
    @Published var isPolling = false
    @Published var status = "Pronto"
    @Published var peripherals: [ObdPeripheral] = []
    @Published var readings: [ObdPid: ObdReading] = [:]
    @Published var logs: [DiagnosticLogEntry] = [.info("App avviata")]
    @Published var pidLabLogs: [PidLabLogEntry] = []
    @Published var pidLabStatus = "Solo comandi di lettura. Nessuna scrittura o codifica centralina."

    private var transport: ObdTransport?
    private var client: Elm327Client?
    private var eventsTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private let transportFactory: TransportFactory

    init(transportFactory: TransportFactory? = nil) {
        self.transportFactory = transportFactory ?? Self.defaultTransportFactory
    }

    func configureTransport() {
        eventsTask?.cancel()
        pollingTask?.cancel()
        transport?.disconnect()
        let newTransport = transportFactory(adapterMode)
        transport = newTransport
        client = Elm327Client(transport: newTransport)
        peripherals.removeAll()
        readings.removeAll()
        isConnected = false
        isPolling = false
        status = adapterMode.title

        eventsTask = Task { [weak self] in
            guard let self else { return }
            for await event in newTransport.events {
                await self.handle(event)
            }
        }
    }

    func selectMode(_ mode: AdapterMode) {
        guard adapterMode != mode else { return }
        adapterMode = mode
        configureTransport()
        startScan()
    }

    func startScan() {
        if transport == nil {
            configureTransport()
        }
        transport?.startScanning()
    }

    func connect(to peripheral: ObdPeripheral) {
        guard let transport, let client else { return }
        Task {
            do {
                status = "Connessione a \(peripheral.name)"
                try await transport.connect(to: peripheral.id)
                status = "Inizializzazione ELM327"
                try await client.initialize()
                isConnected = true
                status = "Connesso"
                logs.append(.info("ELM327 inizializzato"))
                startPolling()
            } catch {
                status = error.localizedDescription
                logs.append(.error(error.localizedDescription))
            }
        }
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        transport?.disconnect()
        isPolling = false
        isConnected = false
        status = "Disconnesso"
    }

    func startPolling() {
        guard let client else { return }
        pollingTask?.cancel()
        isPolling = true
        pollingTask = Task {
            while !Task.isCancelled {
                for pid in ObdPid.allCases {
                    do {
                        let reading = try await client.read(pid)
                        readings[pid] = reading
                    } catch {
                        logs.append(.error("\(pid.command): \(error.localizedDescription)"))
                    }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func commandDecision(for command: String) -> ObdCommandPolicy.Decision {
        ObdCommandPolicy.evaluate(command)
    }

    func sendPidLabCommand(_ rawCommand: String, warning: String?) async {
        guard let client else {
            pidLabStatus = "Trasporto non configurato."
            return
        }
        guard isConnected else {
            pidLabStatus = "Connetti prima un adattatore o usa Mock Adapter."
            return
        }

        let command = ObdCommandPolicy.normalize(rawCommand)
        let decision = ObdCommandPolicy.evaluate(command)
        let canSend: Bool
        switch decision {
        case .allowStandard:
            canSend = true
        case .warnNonStandard:
            canSend = warning != nil
        case .block(let reason):
            pidLabStatus = reason
            return
        }
        guard canSend else {
            pidLabStatus = "Comando non confermato."
            return
        }

        let shouldRestartPolling = isPolling
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        pidLabStatus = "Invio \(command)"

        do {
            let response = try await client.sendRawReadCommand(command)
            let entry = PidLabLogEntry(
                adapterMode: adapterMode.title,
                command: command,
                response: response,
                isStandardRead: warning == nil,
                warning: warning
            )
            pidLabLogs.insert(entry, at: 0)
            pidLabStatus = "Risposta ricevuta"
        } catch {
            let entry = PidLabLogEntry(
                adapterMode: adapterMode.title,
                command: command,
                response: "ERROR: \(error.localizedDescription)",
                isStandardRead: warning == nil,
                warning: warning
            )
            pidLabLogs.insert(entry, at: 0)
            pidLabStatus = error.localizedDescription
            logs.append(.error("PID Lab \(command): \(error.localizedDescription)"))
        }

        if pidLabLogs.count > 500 {
            pidLabLogs.removeLast(pidLabLogs.count - 500)
        }
        if shouldRestartPolling, isConnected {
            startPolling()
        }
    }

    func clearPidLabLogs() {
        pidLabLogs.removeAll()
        pidLabStatus = "Log PID Lab pulito."
    }

    var pidLabJSONExport: PidLabJSONExport {
        PidLabJSONExport(data: PidLabLogExporter.jsonData(from: pidLabLogs))
    }

    var pidLabCSVExport: PidLabCSVExport {
        PidLabCSVExport(data: PidLabLogExporter.csvData(from: pidLabLogs))
    }

    private func handle(_ event: ObdTransportEvent) {
        switch event {
        case .stateChanged(let value):
            status = value
            logs.append(.info(value))
        case .discovered(let peripheral):
            if let index = peripherals.firstIndex(where: { $0.id == peripheral.id }) {
                peripherals[index] = peripheral
            } else {
                peripherals.append(peripheral)
            }
        case .connected(let peripheral):
            status = "Connesso a \(peripheral.name)"
        case .disconnected(let reason):
            isConnected = false
            isPolling = false
            status = reason.map { "Disconnesso: \($0)" } ?? "Disconnesso"
        case .log(let entry):
            logs.append(entry)
        }

        if logs.count > 400 {
            logs.removeFirst(logs.count - 400)
        }
    }

    private static func defaultTransportFactory(mode: AdapterMode) -> ObdTransport {
        switch mode {
        case .mock: return MockObdTransport()
        case .liveBluetooth: return BleObdTransport()
        }
    }
}
