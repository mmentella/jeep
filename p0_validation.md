# P0 validation report

Data audit: 2026-05-30

Ambiente audit: `C:\Users\Foxyh\Documents\jeep`, PowerShell, Windows.  
Nota oggettiva: in questo ambiente `swift --version` e `xcodebuild -list -project ObdJeep.xcodeproj` falliscono per comando non trovato. I test sono stati censiti staticamente, ma non eseguiti runtime qui.

## 1. Command Queue

### Esiste un solo punto di ingresso per i comandi?

Verdetto: SI per i comandi applicativi verso ELM327.

Evidenze:

```text
rg -n "queue.execute|transport.send|writeValue|sendManualReadCommand|client.read|client.initialize|sendPidLabCommand|startPolling\(" ObdJeep ObdJeepTests docs

ObdJeep\ELM327\Elm327CommandQueue.swift:17: try await self.transport.send(command.command)
ObdJeep\ELM327\Elm327Client.swift:11: _ = try await queue.execute(Elm327Command(command: "ATZ", timeout: 5.0, source: .initialization))
ObdJeep\ELM327\Elm327Client.swift:14: _ = try await queue.execute(Elm327Command(command: command, timeout: 2.0, expectedResponsePrefix: "OK", source: .initialization))
ObdJeep\ELM327\Elm327Client.swift:20: let response = try await queue.execute(Elm327Command(
ObdJeep\ELM327\Elm327Client.swift:31: try await queue.execute(Elm327Command(command: command, timeout: 5.0, source: .manual))
ObdJeep\OBD\ObdPollingScheduler.swift:22: let reading = try await client.read(pid)
ObdJeep\UI\ObdDashboardViewModel.swift:90: try await client.initialize()
ObdJeep\UI\ObdDashboardViewModel.swift:168: let response = try await client.sendManualReadCommand(command)
ObdJeep\Bluetooth\BleObdTransport.swift:79: peripheral.writeValue(data, for: writeCharacteristic, type: writeType)
```

Solo `Elm327CommandQueue.swift:17` chiama `ObdTransport.send(_:)` nel codice applicativo. `BleObdTransport.swift:79` e' la write fisica del transport, non un bypass applicativo.

### Esistono ancora write dirette verso il transport?

Verdetto:

- Direct call a `ObdTransport.send(_:)` fuori dalla queue: NO, non trovata.
- Direct BLE write raw: SI, esiste in `BleObdTransport.send(_:)`, come implementazione del transport.

Evidenza:

```text
ObdJeep\Bluetooth\BleObdTransport.swift:63: func send(_ command: String) async throws -> String
ObdJeep\Bluetooth\BleObdTransport.swift:79: peripheral.writeValue(data, for: writeCharacteristic, type: writeType)
```

### Elenco completo dei punti che possono inviare comandi

Punti applicativi:

| Punto | File | Percorso verso invio |
|---|---|---|
| Inizializzazione ELM327 | `ObdJeep\ELM327\Elm327Client.swift:10-15` | `initialize()` -> `queue.execute(...)` |
| Polling PID standard | `ObdJeep\OBD\ObdPollingScheduler.swift:22` + `ObdJeep\ELM327\Elm327Client.swift:18-28` | scheduler -> `client.read(pid)` -> `queue.execute(...)` |
| PID Lab manuale | `ObdJeep\UI\ObdDashboardViewModel.swift:135-195` + `ObdJeep\ELM327\Elm327Client.swift:30-31` | view model -> `client.sendManualReadCommand(command)` -> `queue.execute(...)` |
| Test queue | `ObdJeepTests\Elm327CommandQueueTests.swift:9-23` | test -> `queue.execute(...)` |

Punto transport:

| Punto | File | Nota |
|---|---|---|
| BLE write fisica | `ObdJeep\Bluetooth\BleObdTransport.swift:79` | chiamata solo dentro `BleObdTransport.send(_:)` |

### Dimostrazione che passano tutti dalla queue

Evidenza statica:

```text
rg -n "send\(|execute\(|writeValue" ObdJeep --glob "*.swift"

ObdJeep\ELM327\Elm327CommandQueue.swift:12: func execute(_ command: Elm327Command) async throws -> Elm327Response
ObdJeep\ELM327\Elm327CommandQueue.swift:17: try await self.transport.send(command.command)
ObdJeep\ELM327\Elm327Client.swift:11: _ = try await queue.execute(...)
ObdJeep\ELM327\Elm327Client.swift:14: _ = try await queue.execute(...)
ObdJeep\ELM327\Elm327Client.swift:20: let response = try await queue.execute(...)
ObdJeep\ELM327\Elm327Client.swift:31: try await queue.execute(...)
ObdJeep\Bluetooth\BleObdTransport.swift:79: peripheral.writeValue(...)
```

Documento di architettura coerente:

```text
docs\elm327_command_queue.md:7: Elm327CommandQueue is the only application component allowed to call ObdTransport.send(_:).
docs\elm327_command_queue.md:36: Because Elm327CommandQueue is an actor, concurrent callers await their turn automatically.
docs\elm327_command_queue.md:67: execute through the same Elm327CommandQueue;
```

## 2. Concorrenza

### Esistono race condition note?

Verdetto: SI, rischi residui identificati.

1. `PendingResponse` non e' protetto da actor/lock.
   - Accessi da `BleObdTransport.send(_:)`, `disconnect()`, `didDisconnectPeripheral`, `didUpdateValueFor`, cancellation handler.
   - Evidenza:

```text
ObdJeep\Bluetooth\BleObdTransport.swift:12: private var pendingResponse = PendingResponse()
ObdJeep\Bluetooth\BleObdTransport.swift:60: pendingResponse.cancel(with: ObdTransportError.notConnected)
ObdJeep\Bluetooth\BleObdTransport.swift:78: return try await pendingResponse.wait {
ObdJeep\Bluetooth\BleObdTransport.swift:82: pendingResponse.cancel(with: ObdTransportError.timeout)
ObdJeep\Bluetooth\BleObdTransport.swift:122: pendingResponse.cancel(with: error ?? ObdTransportError.notConnected)
ObdJeep\Bluetooth\BleObdTransport.swift:167: pendingResponse.cancel(with: error)
ObdJeep\Bluetooth\BleObdTransport.swift:175: pendingResponse.resume(with: chunk)
ObdJeep\Bluetooth\BleObdTransport.swift:181: private final class PendingResponse
```

2. `connectContinuation` non e' protetto da actor/lock e puo' essere toccato da flow async e callback CoreBluetooth.
   - Evidenza:

```text
ObdJeep\Bluetooth\BleObdTransport.swift:14: private var connectContinuation: CheckedContinuation<Void, Error>?
ObdJeep\Bluetooth\BleObdTransport.swift:48: connectContinuation = continuation
ObdJeep\Bluetooth\BleObdTransport.swift:92: connectContinuation?.resume()
ObdJeep\Bluetooth\BleObdTransport.swift:117: connectContinuation?.resume(throwing: error ?? ObdTransportError.peripheralNotFound)
ObdJeep\Bluetooth\BleObdTransport.swift:130: connectContinuation?.resume(throwing: error)
ObdJeep\Bluetooth\BleObdTransport.swift:135: connectContinuation?.resume(throwing: ObdTransportError.serviceNotFound)
ObdJeep\Bluetooth\BleObdTransport.swift:144: connectContinuation?.resume(throwing: error)
```

3. `Elm327CommandQueue.withTimeout` cancella il task perdente, ma il transport BLE non dimostra abort della write gia' partita; la risposta tardiva puo' arrivare dopo timeout e interagire con lo stato `pendingResponse`.

### Polling e PID Lab possono ancora sovrapporsi?

Verdetto:

- Overlap fisico sul transport: NO, se tutti i comandi passano dalla queue.
- Overlap logico: SI, un polling gia' in volo puo' restare davanti al comando PID Lab.

Evidenze:

```text
ObdJeep\UI\ObdDashboardViewModel.swift:162: let shouldRestartPolling = pollingScheduler.isRunning
ObdJeep\UI\ObdDashboardViewModel.swift:163: pollingScheduler.stop()
ObdJeep\UI\ObdDashboardViewModel.swift:168: let response = try await client.sendManualReadCommand(command)
ObdJeep\UI\ObdDashboardViewModel.swift:194: if shouldRestartPolling, isConnected {
ObdJeep\UI\ObdDashboardViewModel.swift:195: startPolling()
```

Il test `testSerializesCommands` copre due submit concorrenti e verifica `maxInFlight == 1`, ma non copre specificamente stop polling + manual command con polling gia' in await.

### Quali scenari non sono coperti?

- Disconnect mentre un comando BLE e' in attesa.
- Bluetooth poweredOff/resetting durante `send`.
- Reconnect automatico dopo disconnessione inattesa.
- Risposta tardiva dopo timeout del comando.
- Doppio resume/cancel della stessa continuation.
- PID Lab premuto ripetutamente/concorrenza di due manual commands.
- Cambio adapter mode mentre comando e' in volo.
- Test su dispositivo reale/iPhone BLE state machine.

## 3. Parser

Parser valutato: `Elm327FrameParser.parse(rawText:command:)`. Dove il timeout non passa dal parser, l'output e' della queue.

| Caso | Input raw | Output parser |
|---|---|---|
| OK | `"OK\r>"` con expected `OK` | `Elm327Response(isOK: true, promptSeen: true, lines: ["OK"], frames: [])` |
| NO DATA | `"NO DATA\r>"` | `Elm327Error.noData(raw: "NO DATA\r>")` |
| STOPPED | `"STOPPED\r>"` | `Elm327Error.stopped(raw: "STOPPED\r>")` |
| SEARCHING... | `"SEARCHING...\r>"` | `Elm327Error.searching(raw: "SEARCHING...\r>")` |
| BUS ERROR | `"BUS ERROR\r>"` | `Elm327Error.busError(raw: "BUS ERROR\r>")` |
| CAN ERROR | `"CAN ERROR\r>"` | `Elm327Error.canError(raw: "CAN ERROR\r>")` |
| UNABLE TO CONNECT | `"UNABLE TO CONNECT\r>"` | `Elm327Error.unableToConnect(raw: "UNABLE TO CONNECT\r>")` |
| timeout | comando `"010C"`, timeout `0.05`, transport delay `0.5s` | `Elm327Error.timeout(command: "010C", seconds: 0.05)` dalla queue, non dal parser |
| risposta multilinea | `"SEARCHING...\r41 0C 0F A0\r>"` con expected `410C` | `Elm327Response(lines: ["SEARCHING...", "41 0C 0F A0"], frames[0].bytes: [0x41, 0x0C, 0x0F, 0xA0], promptSeen: true)` |
| risposta malformata | `"7E8 Z1\r>"` | `Elm327Error.malformedFrame(raw: "7E8 Z1\r>")` |

Evidenze test:

```text
ObdJeepTests\Elm327FrameParserTests.swift:5: testParsesOkResponse
ObdJeepTests\Elm327FrameParserTests.swift:14: testParsesSearchingThenFrame
ObdJeepTests\Elm327FrameParserTests.swift:29: testThrowsTypedAdapterErrors
ObdJeepTests\Elm327FrameParserTests.swift:49: testThrowsMalformedFrame
ObdJeepTests\Elm327CommandQueueTests.swift:18: testCommandTimeout
```

Nota copertura: `SEARCHING...` senza frame e' gestito dal codice, ma non ha test dedicato separato; il test esistente copre `SEARCHING...` seguito da frame.

## 4. Test

### Elenco test esistenti

| Test | Scopo | Risultato audit |
|---|---|---|
| `ObdValueParserTests.testParsesStandardPids` | Parsing valori PID standard | Presente, non eseguito qui |
| `ObdValueParserTests.testIgnoresElmNoiseAndPrompt` | Ignora noise/prompt ELM | Presente, non eseguito qui |
| `ObdValueParserTests.testParsesCompactResponses` | Parsing risposta compatta | Presente, non eseguito qui |
| `ObdValueParserTests.testParsesResponseWithCanHeaderPrefix` | Parsing con CAN header | Presente, non eseguito qui |
| `ObdValueParserTests.testRejectsNoData` | Rifiuto NO DATA | Presente, non eseguito qui |
| `ObdValueParserTests.testRejectsPidMismatch` | Rifiuto PID mismatch | Presente, non eseguito qui |
| `Elm327FrameParserTests.testParsesOkResponse` | Parsing OK | Presente, non eseguito qui |
| `Elm327FrameParserTests.testParsesSearchingThenFrame` | SEARCHING + frame | Presente, non eseguito qui |
| `Elm327FrameParserTests.testParsesFrameWithCanHeader` | Frame con header CAN | Presente, non eseguito qui |
| `Elm327FrameParserTests.testThrowsTypedAdapterErrors` | NO DATA/STOPPED/BUS/CAN/UNABLE | Presente, non eseguito qui |
| `Elm327FrameParserTests.testThrowsMalformedFrame` | Frame malformato | Presente, non eseguito qui |
| `Elm327FrameParserTests.testThrowsNegativeResponseInsideCanFrame` | Negative ECU response `7F` | Presente, non eseguito qui |
| `Elm327CommandQueueTests.testSerializesCommands` | Serializzazione queue, `maxInFlight == 1` | Presente, non eseguito qui |
| `Elm327CommandQueueTests.testCommandTimeout` | Timeout comando queue | Presente, non eseguito qui |
| `ObdCommandPolicyTests.testAllowsStandardReadCommands` | Policy allow read standard/AT consentiti | Presente, non eseguito qui |
| `ObdCommandPolicyTests.testWarnsForProprietaryReadService` | Warning servizio proprietario read | Presente, non eseguito qui |
| `ObdCommandPolicyTests.testBlocksWriteAndProgrammingServices` | Blocco servizi write/programming | Presente, non eseguito qui |
| `ObdCommandPolicyTests.testBlocksSecurityAccess` | Blocco security access | Presente, non eseguito qui |

Comandi di verifica:

```text
rg -n "func test" ObdJeepTests
```

Totale test: 18.

Risultato esecuzione:

```text
swift --version
=> The term 'swift' is not recognized...

xcodebuild -list -project ObdJeep.xcodeproj
=> The term 'xcodebuild' is not recognized...
```

Parser coverage stimata:

- `Elm327FrameParser`: circa 80% dei casi P0 richiesti coperti da test diretti o combinati. Mancano test dedicati per `SEARCHING...` senza frame e per timeout parser-side, che in realta' e' queue-side.
- `ObdValueParser`: buona sui PID standard principali, noise, compact, CAN header, NO DATA, mismatch; non copre tutti gli errori ELM tipizzati del frame parser.

Queue coverage stimata:

- Circa 45%.
- Coperto: serializzazione base e timeout.
- Non coperto: disconnect durante comando, BLE state change, reconnect, risposta tardiva, errore transport, cancellazione task polling/manuale, starvation/FIFO sotto carico, doppio manual command.

## 5. Robustezza BLE

### Reconnect

Verdetto: NON verificato / non implementato come automatic reconnect.

Evidenza:

```text
ObdJeep\OBD\ObdConnectionState.swift:9: case reconnecting
```

`reconnecting` esiste nello stato, ma non emergono chiamate che impostano `connectionState = .reconnecting` o ritentativi automatici dopo `didDisconnectPeripheral`.

### Disconnect inatteso

Verdetto: parzialmente gestito.

Evidenza:

```text
ObdJeep\Bluetooth\BleObdTransport.swift:121: func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
ObdJeep\Bluetooth\BleObdTransport.swift:122: pendingResponse.cancel(with: error ?? ObdTransportError.notConnected)
ObdJeep\Bluetooth\BleObdTransport.swift:123: emit(.disconnected(error?.localizedDescription))
ObdJeep\UI\ObdDashboardViewModel.swift:225: case .disconnected(let reason):
ObdJeep\UI\ObdDashboardViewModel.swift:226: isConnected = false
ObdJeep\UI\ObdDashboardViewModel.swift:227: isPolling = false
ObdJeep\UI\ObdDashboardViewModel.swift:228: connectionState = .disconnected
```

Limite: il view model marca `isPolling = false`, ma non chiama `pollingScheduler.stop()` nel branch `.disconnected`; il task di polling potrebbe continuare fino a errori/cancellazione altrove.

### Timeout comando durante perdita connessione

Verdetto: parzialmente gestito, non testato.

Evidenza:

```text
ObdJeep\ELM327\Elm327CommandQueue.swift:16: let raw = try await withTimeout(seconds: command.timeout, command: command.command) {
ObdJeep\ELM327\Elm327CommandQueue.swift:17: try await self.transport.send(command.command)
ObdJeep\Bluetooth\BleObdTransport.swift:60: pendingResponse.cancel(with: ObdTransportError.notConnected)
ObdJeep\Bluetooth\BleObdTransport.swift:82: pendingResponse.cancel(with: ObdTransportError.timeout)
ObdJeep\Bluetooth\BleObdTransport.swift:122: pendingResponse.cancel(with: error ?? ObdTransportError.notConnected)
```

Limite: assenza test su ordering tra timeout queue, cancellation handler e `didDisconnectPeripheral`.

### Cambio stato bluetooth iPhone

Verdetto: solo notificato, non hardenizzato.

Evidenza:

```text
ObdJeep\Bluetooth\BleObdTransport.swift:100: func centralManagerDidUpdateState(_ central: CBCentralManager) {
ObdJeep\Bluetooth\BleObdTransport.swift:101: emit(.stateChanged(central.state.description))
```

Manca evidenza che `poweredOff`, `resetting`, `unauthorized` cancellino connessioni/comandi pendenti o fermino polling.

## 6. Debito tecnico residuo

### CRITICO

- `PendingResponse` e `connectContinuation` non sono protetti da serial executor/lock; rischio doppio resume/cancel o race tra async command, timeout, disconnect e callback BLE.
- Nessun test runtime eseguito in questo ambiente; impossibile validare oggettivamente build/test prima del test su adattatore reale.
- BLE state changes non cancellano esplicitamente comando pendente/polling salvo percorso `didDisconnectPeripheral`.

### IMPORTANTE

- Reconnect automatico non implementato/non evidenziato, nonostante stato `reconnecting`.
- Branch `.disconnected` del view model non chiama `pollingScheduler.stop()`.
- PID Lab ferma il polling, ma un comando polling gia' in volo puo' completare o timeout prima del manual command.
- Mancano test per disconnect, reconnect, state change Bluetooth, risposta tardiva post-timeout.
- `SEARCHING...` senza risposta finale e' gestito dal parser ma non ha test dedicato.

### MINORE

- Coverage queue limitata a serializzazione base e timeout.
- Coverage parser buona ma non esaustiva sugli adapter errors (`BUFFER FULL`, `RX ERROR`, `?`) nel report P0.
- Documento architetturale coerente, ma non sostituisce test automatici su casi BLE reali.

## 7. Go/No-Go

NO-GO

Motivi esatti:

1. I test non sono stati eseguiti in questo ambiente: mancano `swift` e `xcodebuild`, quindi non c'e' evidenza runtime locale.
2. La robustezza BLE P0 non e' completa: reconnect non dimostrato, cambio stato Bluetooth solo notificato, disconnect inatteso solo parzialmente gestito.
3. Esiste rischio di race su `PendingResponse`/`connectContinuation` durante timeout, disconnect e callback BLE.
4. La queue protegge dall'overlap fisico dei comandi applicativi, ma non ci sono test per scenari reali di perdita connessione o risposta tardiva.
