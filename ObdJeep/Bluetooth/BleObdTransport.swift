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
    private let pendingResponse = PendingResponse()
    private let connectContinuation = OneShotContinuation<Void>()
    private let responseBufferQueue = DispatchQueue(label: "com.obdjeep.ble.response-buffer")
    private var responseBuffer = Data()

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
        try await connectContinuation.wait {
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
        connectContinuation.cancel(with: ObdTransportError.notConnected)
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

        clearResponseBuffer()
        emit(.log(.outgoing(command.trimmingCharacters(in: .whitespacesAndNewlines))))
        return try await withTaskCancellationHandler {
            // BLE ELM327 adapters vary: some accept writeWithoutResponse only, while others
            // require write-with-response. Use the advertised characteristic property.
            let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            return try await pendingResponse.wait {
                peripheral.writeValue(data, for: writeCharacteristic, type: writeType)
            }
        } onCancel: {
            pendingResponse.cancel(with: ObdTransportError.timeout)
        }
    }

    private func emit(_ event: ObdTransportEvent) {
        eventContinuation.yield(event)
    }

    private func finishDiscoveryIfReady(for peripheral: CBPeripheral) {
        guard writeCharacteristic != nil, notifyCharacteristic != nil else { return }
        guard connectContinuation.resume(returning: ()) else { return }
        let name = peripheral.name ?? "OBD BLE"
        emit(.connected(ObdPeripheral(id: peripheral.identifier, name: name, rssi: 0)))
    }

    private func clearResponseBuffer() {
        responseBufferQueue.sync {
            responseBuffer.removeAll()
        }
    }

    private func appendResponseData(_ data: Data) -> String? {
        responseBufferQueue.sync {
            responseBuffer.append(data)
            guard let chunk = String(data: responseBuffer, encoding: .ascii), chunk.contains(">") else {
                return nil
            }
            responseBuffer.removeAll()
            return chunk
        }
    }
}

extension BleObdTransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit(.stateChanged(central.state.description))
        switch central.state {
        case .poweredOn, .unknown:
            break
        case .resetting, .unsupported, .unauthorized, .poweredOff:
            connectContinuation.cancel(with: ObdTransportError.bluetoothUnavailable(central.state.description))
            pendingResponse.cancel(with: ObdTransportError.bluetoothUnavailable(central.state.description))
            connectedPeripheral = nil
            writeCharacteristic = nil
            notifyCharacteristic = nil
            clearResponseBuffer()
        @unknown default:
            connectContinuation.cancel(with: ObdTransportError.bluetoothUnavailable(central.state.description))
            pendingResponse.cancel(with: ObdTransportError.bluetoothUnavailable(central.state.description))
            clearResponseBuffer()
        }
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
        connectContinuation.cancel(with: error ?? ObdTransportError.peripheralNotFound)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        clearResponseBuffer()
        connectContinuation.cancel(with: error ?? ObdTransportError.notConnected)
        pendingResponse.cancel(with: error ?? ObdTransportError.notConnected)
        emit(.disconnected(error?.localizedDescription))
    }
}

extension BleObdTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectContinuation.cancel(with: error)
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            connectContinuation.cancel(with: ObdTransportError.serviceNotFound)
            return
        }
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectContinuation.cancel(with: error)
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
        guard let chunk = appendResponseData(data) else { return }
        emit(.log(.incoming(chunk.trimmingCharacters(in: .whitespacesAndNewlines))))
        pendingResponse.resume(with: chunk)
    }
}

private final class PendingResponse {
    private let storage = OneShotContinuation<String>()

    func wait(start: () -> Void) async throws -> String {
        try await storage.wait(start: start)
    }

    @discardableResult
    func resume(with value: String) -> Bool {
        storage.resume(returning: value)
    }

    @discardableResult
    func cancel(with error: Error) -> Bool {
        storage.cancel(with: error)
    }
}

private final class OneShotContinuation<Value> {
    private let queue = DispatchQueue(label: "com.obdjeep.ble.one-shot-continuation")
    private var continuation: CheckedContinuation<Value, Error>?

    func wait(start: () -> Void) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let accepted = queue.sync { () -> Bool in
                guard self.continuation == nil else { return false }
                self.continuation = continuation
                return true
            }

            guard accepted else {
                continuation.resume(throwing: ObdTransportError.timeout)
                return
            }

            start()
        }
    }

    @discardableResult
    func resume(returning value: Value) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func cancel(with error: Error) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(throwing: error)
        return true
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        queue.sync {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
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
