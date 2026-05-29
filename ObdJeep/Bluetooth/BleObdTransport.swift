import CoreBluetooth
import Foundation

final class BleObdTransport: NSObject, ObdTransport {
    private let eventStream: AsyncStream<ObdTransportEvent>
    private let eventContinuation: AsyncStream<ObdTransportEvent>.Continuation
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var pendingResponse = PendingResponse()
    private var responseBuffer = Data()
    private var connectContinuation: CheckedContinuation<Void, Error>?

    var events: AsyncStream<ObdTransportEvent> { eventStream }

    override init() {
        var continuation: AsyncStream<ObdTransportEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            emit(.stateChanged("Bluetooth non pronto: \(central.state.description)"))
            return
        }
        emit(.stateChanged("Scansione BLE in corso"))
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        central.stopScan()
        emit(.stateChanged("Scansione interrotta"))
    }

    func connect(to peripheralID: UUID) async throws {
        guard let peripheral = peripherals[peripheralID] else {
            throw ObdTransportError.peripheralNotFound
        }
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            central.connect(peripheral, options: nil)
        }
    }

    func disconnect() {
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingResponse.cancel(with: ObdTransportError.notConnected)
    }

    func send(_ command: String) async throws -> String {
        guard let peripheral = connectedPeripheral, let writeCharacteristic else {
            throw ObdTransportError.notConnected
        }
        let normalized = command.hasSuffix("\r") ? command : command + "\r"
        guard let data = normalized.data(using: .ascii) else {
            throw ObdTransportError.invalidEncoding
        }

        responseBuffer.removeAll()
        defer { pendingResponse.cancel(with: ObdTransportError.timeout) }
        emit(.log(.outgoing(command.trimmingCharacters(in: .whitespacesAndNewlines))))
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.pendingResponse.wait()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                throw ObdTransportError.timeout
            }

            // BLE ELM327 adapters vary: some accept writeWithoutResponse only, while others
            // require write-with-response. Use the advertised characteristic property.
            let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: writeCharacteristic, type: writeType)

            guard let response = try await group.next() else {
                throw ObdTransportError.timeout
            }
            group.cancelAll()
            return response
        }
    }

    private func emit(_ event: ObdTransportEvent) {
        eventContinuation.yield(event)
    }

    private func finishDiscoveryIfReady(for peripheral: CBPeripheral) {
        guard writeCharacteristic != nil, notifyCharacteristic != nil else { return }
        connectContinuation?.resume()
        connectContinuation = nil
        let name = peripheral.name ?? "OBD BLE"
        emit(.connected(ObdPeripheral(id: peripheral.identifier, name: name, rssi: 0)))
    }
}

extension BleObdTransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit(.stateChanged(central.state.description))
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertisedName ?? "Scanner BLE sconosciuto"
        peripherals[peripheral.identifier] = peripheral
        emit(.discovered(ObdPeripheral(id: peripheral.identifier, name: name, rssi: RSSI.intValue)))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        emit(.stateChanged("Connesso a \(peripheral.name ?? "scanner") - ricerca servizi"))
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectContinuation?.resume(throwing: error ?? ObdTransportError.peripheralNotFound)
        connectContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        pendingResponse.cancel(with: error ?? ObdTransportError.notConnected)
        emit(.disconnected(error?.localizedDescription))
    }
}

extension BleObdTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            connectContinuation?.resume(throwing: ObdTransportError.serviceNotFound)
            connectContinuation = nil
            return
        }
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            return
        }

        service.characteristics?.forEach { characteristic in
            let properties = characteristic.properties
            if properties.contains(.notify) || properties.contains(.indicate) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if properties.contains(.write) || properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }
        }

        // BLE-to-UART UUIDs are not fully standardized across OBD adapters and clones.
        // Property-based discovery keeps Vgate-like devices and common BLE UART bridges usable.
        finishDiscoveryIfReady(for: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            pendingResponse.cancel(with: error)
            return
        }
        guard let data = characteristic.value else { return }
        responseBuffer.append(data)
        guard let chunk = String(data: responseBuffer, encoding: .ascii) else { return }
        if chunk.contains(">") {
            let cleaned = chunk.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            emit(.log(.incoming(cleaned)))
            pendingResponse.resume(with: cleaned)
            responseBuffer.removeAll()
        }
    }
}

private final class PendingResponse {
    private var continuation: CheckedContinuation<String, Error>?

    func wait() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with value: String) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func cancel(with error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: return "Stato Bluetooth sconosciuto"
        case .resetting: return "Bluetooth in reset"
        case .unsupported: return "Bluetooth non supportato"
        case .unauthorized: return "Bluetooth non autorizzato"
        case .poweredOff: return "Bluetooth spento"
        case .poweredOn: return "Bluetooth pronto"
        @unknown default: return "Stato Bluetooth non gestito"
        }
    }
}
