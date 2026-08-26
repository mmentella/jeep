# Post-fix validation report

Data audit: 2026-05-30

Ambiente audit: `C:\Users\Foxyh\Documents\jeep`, PowerShell, Windows.

Nota oggettiva: in questo ambiente `swift --version` e `xcodebuild -list -project ObdJeep.xcodeproj` falliscono per comando non trovato. La validazione seguente e' quindi una review statica post-fix con test automatici aggiunti, ma non eseguiti localmente.

## Sintesi fix P0

Le correzioni critiche sono limitate a:

- serializzazione dello stato di `PendingResponse`;
- serializzazione dello stato di `connectContinuation`;
- gestione one-shot delle continuation: primo evento terminale vince, eventi successivi sono no-op;
- cancellazione esplicita del comando pendente su disconnect e stati Bluetooth non utilizzabili;
- serializzazione del buffer raw di risposta BLE;
- test automatici per gli scenari critici di timeout, disconnect, risposta tardiva, concorrenza e cancellazione task.

Non sono stati implementati:

- PID Jeep;
- reconnect automatico;
- modifiche UI;
- nuove funzionalita' applicative.

## Tabella di validazione

| Area | Stato | Note |
| ---- | ----- | ---- |
| Race condition su `PendingResponse` | PASS | `PendingResponse` delega a `OneShotContinuation<String>`, che usa una coda seriale privata e consuma la continuation con `takeContinuation()` prima del resume/cancel. |
| Race condition su `connectContinuation` | PASS | La continuation di connect e' ora gestita da `OneShotContinuation<Void>`; success, fail, disconnect e Bluetooth state change passano dallo stesso percorso serializzato. |
| Double resume possibile | PASS | `resume(returning:)` e `cancel(with:)` rimuovono atomicamente la continuation prima di invocare `resume`; ogni chiamata successiva ritorna `false` e non resume-a nulla. |
| Resume dopo cancel | PASS | Dopo `cancel(with:)`, la continuation e' gia' stata rimossa dal contenitore serializzato; una risposta tardiva non ha effetto. |
| Cancel dopo resume | PASS | Dopo `resume(returning:)`, la continuation e' gia' stata rimossa; disconnect/cancel successivi sono no-op. |
| Timeout, disconnect e risposta mutuamente esclusivi | PASS | Ogni evento terminale compete sullo stesso slot one-shot. L'ordine effettivo e' determinato dalla coda seriale; solo il primo evento puo' completare la continuation. |
| Punti non serializzati residui su continuation BLE | PASS | Non rimangono accessi diretti a `CheckedContinuation` in `BleObdTransport` fuori da `OneShotContinuation`. |
| Buffer raw risposta BLE | PASS | `responseBuffer` e' protetto da `responseBufferQueue`, evitando append/remove concorrenti tra `send` e callback BLE. |
| Tutti i comandi passano dalla queue | PASS | L'unica chiamata applicativa a `transport.send(_:)` resta in `Elm327CommandQueue.execute`; la write BLE raw resta confinata a `BleObdTransport.send(_:)`. |
| Disconnect durante comando in-flight | PASS | `disconnect()` cancella `connectContinuation` e `pendingResponse`, azzera characteristic/peripheral e lascia eventuali risposte tardive senza continuation da completare. |
| Bluetooth powered off/resetting/unauthorized durante comando | PASS | `centralManagerDidUpdateState` cancella connect/send pendenti per stati non utilizzabili e pulisce lo stato BLE locale. |
| Transport in stato inconsistente | WARNING | Lo stato BLE locale viene azzerato su disconnect e stati Bluetooth non utilizzabili. Rimane da validare runtime su CoreBluetooth reale per ordering callback specifici del dispositivo. |
| Memory leak evidenti | PASS | Le continuation vengono rimosse al primo terminal event; il buffer viene svuotato su risposta completa, disconnect e stato Bluetooth non utilizzabile. |
| Task che possono restare appesi | WARNING | I test aggiunti coprono timeout/cancel/disconnect e rilascio queue. Serve esecuzione reale con Xcode per confermare che non ci siano hang runtime. |
| Build e test runtime | WARNING | Non eseguibili in questo ambiente: `swift` e `xcodebuild` non sono installati/disponibili. |

## Test automatici aggiunti

| Test | Scenario | Verifica | Bug storico prevenuto |
| ---- | -------- | -------- | --------------------- |
| `testDisconnectDuringInFlightCommandFailsCommand` | Disconnect durante comando in-flight. | Il comando pendente fallisce con `notConnected` e non resta pending. | Continuation appesa o completata dopo disconnect. |
| `testCommandTimeout` | Timeout durante comando in-flight. | La queue produce `Elm327Error.timeout` e il transport simulato non mantiene pending. | Timeout che lascia task pendenti o blocca la queue. |
| `testDisconnectImmediatelyBeforeResponseWinsOverLateResponse` | Disconnect immediatamente prima della risposta. | Il disconnect vince; la risposta tardiva non completa nulla. | Double resume tra disconnect e risposta. |
| `testDisconnectImmediatelyAfterResponseDoesNotCancelCompletedCommand` | Disconnect immediatamente dopo la risposta. | Il comando gia' completato resta success; disconnect successivo non lo cancella. | Cancel dopo resume. |
| `testLateResponseAfterTimeoutIsIgnoredAndNextCommandCanRun` | Risposta tardiva dopo timeout. | La risposta tardiva e' ignorata e il comando successivo passa. | Risposta vecchia che sporca il comando successivo. |
| `testTwoConcurrentCommandsRemainSerialized` | Due comandi concorrenti. | `maxInFlight == 1`; il secondo parte solo dopo il primo. | Overlap fisico sul transport. |
| `testPollingReadAndPidLabCommandRemainSerialized` | Polling + comando PID Lab concorrenti. | `client.read(.rpm)` e manual command passano dalla stessa queue. | Polling e manual command sovrapposti. |
| `testTaskCancellationDuringResponseWaitReleasesQueue` | Cancellazione task durante attesa risposta. | La cancellazione libera il pending e il comando successivo puo' partire. | Queue bloccata da task cancellato. |
| `testTimeoutFollowedByReconnectAllowsNewCommand` | Timeout seguito da reconnect simulato. | Dopo timeout e reconnect manuale, un nuovo comando completa. | Stato transport contaminato dal timeout precedente. |
| `testMultipleRapidDisconnectReconnectCyclesDoNotLeavePendingCommands` | Disconnect/reconnect rapidi simulati. | Ogni ciclo fallisce il comando in-flight e non lascia pending; il comando finale completa. | Accumulo continuation o pending zombie. |

## Copertura aggiuntiva ottenuta

- Percorso `timeout`: coperto da timeout diretto e risposta tardiva post-timeout.
- Percorso `disconnect`: coperto prima, durante e dopo la risposta.
- Percorso `risposta ricevuta`: coperto da completamento normale e protezione contro cancel successivo.
- Percorso `cancellazione task`: coperto da cancellazione esplicita durante attesa.
- Concorrenza applicativa: coperti due comandi concorrenti e polling/manual command concorrenti.
- Recupero manuale post-errore: coperti timeout seguito da reconnect simulato e cicli rapidi disconnect/reconnect.

## Verdetto

NO-GO

Motivazione:

1. La review statica dei fix P0 e' positiva: le race condition critiche su `PendingResponse` e `connectContinuation` risultano eliminate dal nuovo contenitore serializzato one-shot.
2. I test automatici per gli scenari critici sono stati aggiunti, ma non possono essere eseguiti in questo ambiente per assenza di toolchain Swift/Xcode.
3. Prima del test su Vgate iCar Pro 2S reale serve esecuzione su macOS/Xcode della suite `ObdJeepTests`; senza evidenza runtime, non e' corretto dichiarare GO per adattatore reale.

