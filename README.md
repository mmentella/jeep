# OBD Jeep SwiftUI MVP

App iOS nativa SwiftUI per leggere PID OBD-II standard tramite adattatore OBD BLE compatibile ELM327. Questo MVP privilegia architettura testabile, diagnostica raw e mock mode per sviluppare l'interfaccia senza auto collegata.

## Struttura

- `ObdJeep/Bluetooth/ObdTransport.swift`: protocollo comune per qualunque adattatore.
- `ObdJeep/Bluetooth/BleObdTransport.swift`: trasporto CoreBluetooth BLE reale.
- `ObdJeep/Bluetooth/MockObdTransport.swift`: simulatore ELM327 locale con valori realistici e variabili.
- `ObdJeep/ELM327/Elm327Client.swift`: inizializzazione ELM327 e invio comandi.
- `ObdJeep/ELM327/Elm327CommandQueue.swift`: actor seriale che garantisce un solo comando ELM327 in-flight.
- `ObdJeep/ELM327/Elm327FrameParser.swift`: parser raw ELM327 a frame con errori tipizzati.
- `ObdJeep/OBD/ObdPid.swift`: PID standard supportati.
- `ObdJeep/OBD/CustomObdPid.swift`: modello dati per futuri PID custom Jeep/4xe.
- `ObdJeep/OBD/ObdCommandPolicy.swift`: protezioni read-only per il PID Lab.
- `ObdJeep/OBD/ObdValueParser.swift`: parsing robusto risposte ELM327.
- `ObdJeep/UI`: dashboard SwiftUI e schermata diagnostica.
- `ObdJeep/UI/PidLabView.swift`: invio manuale read-only e export log raw.
- `ObdJeepTests`: test unitari del parser.

## PID MVP

- RPM: `010C`
- Speed: `010D`
- Coolant temperature: `0105`
- Control module voltage: `0142`
- Engine load: `0104`
- Throttle position: `0111`

## Prerequisiti

- macOS con Xcode 15 o superiore.
- iPhone reale con iOS 17 o superiore consigliato.
- Account Apple Developer configurato in Xcode per firmare l'app.
- Adattatore OBD-II BLE compatibile ELM327, per esempio Vgate iCar Pro 2S in modalita BLE.

## Build da Xcode

1. Apri `ObdJeep.xcodeproj` in Xcode.
2. Seleziona il target `ObdJeep`.
3. In `Signing & Capabilities`, scegli il tuo team.
4. Seleziona un iPhone reale come destinazione.
5. Premi Run.

## GitHub Actions CI

Il repository include `.github/workflows/ios-ci.yml`.

La pipeline parte su push, pull request verso `main` e avvio manuale da `Actions > iOS CI > Run workflow`. Usa `macos-latest`, seleziona Xcode, trova automaticamente un simulatore iPhone disponibile e lancia:

```sh
xcodebuild test \
  -project ObdJeep.xcodeproj \
  -scheme ObdJeep \
  -destination "platform=iOS Simulator,name=<simulator>" \
  CODE_SIGNING_ALLOWED=NO
```

Questa CI non firma l'app e non produce una build installabile su iPhone. Serve per verificare compilazione e unit test. Per Bluetooth reale e installazione su dispositivo servono ancora macOS, Xcode, signing Apple e un iPhone fisico.

## Test parser

In Xcode:

1. Seleziona lo schema `ObdJeep`.
2. Premi `Command-U`.

I test coprono le formule dei PID standard, rumore ELM327 come `SEARCHING...`, casi di errore come `NO DATA` e la policy di sicurezza del PID Lab.

## P0 hardening

Il core ELM327 usa ora una command queue seriale:

- polling automatico, init e PID Lab passano tutti da `Elm327CommandQueue`;
- ogni comando ha timeout, source e optional expected response prefix;
- il transport BLE/mock resta raw I/O e non viene chiamato direttamente dalla UI;
- il PID Lab sospende il polling, invia il comando manuale tramite queue e poi riattiva il polling;
- `Elm327FrameParser` conserva raw text e normalized text e produce errori tipizzati per `NO DATA`, `STOPPED`, `BUS ERROR`, `CAN ERROR`, `UNABLE TO CONNECT`, timeout e frame malformati.

Design dettagliato: `docs/elm327_command_queue.md`.

## Test su iPhone reale

1. Collega l'adattatore OBD alla porta OBD-II dell'auto.
2. Metti il quadro in modalita accessori o avvia il veicolo.
3. Avvia l'app su iPhone.
4. Seleziona `Live Bluetooth` nel selettore in alto nella dashboard.
5. Tocca `Cerca`, seleziona lo scanner trovato e poi `Connetti`.
6. Apri `Diagnostica` per vedere comandi TX e risposte RX raw ELM327.

Se la dashboard resta senza dati, controlla prima la schermata diagnostica. Risposte come `NO DATA`, `UNABLE TO CONNECT` o timeout indicano problemi di protocollo, veicolo spento, adattatore non compatibile BLE oppure inizializzazione ELM327 incompleta.

## Limiti Bluetooth Classic/SPP su iOS

iOS non espone Bluetooth Classic SPP alle app generiche. Molti scanner ELM327 economici sono solo Bluetooth Classic/SPP: funzionano con Android ma non con iOS. Per questa app serve un adattatore BLE reale, oppure un dispositivo MFi con protocolli supportati da Apple. Il codice cerca caratteristiche BLE leggibili/scrivibili per restare compatibile con piu adattatori BLE-to-UART, ma i cloni possono usare UUID e comportamenti differenti.

## Mock Adapter

La modalita `Mock Adapter` e attiva di default. Simula uno scanner ELM327 completo dal punto di vista dell'app:

- espone una periferica fittizia `Mock ELM327 BLE`;
- risponde ai comandi di setup `ATZ`, `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATSP0`;
- genera risposte ELM327 standard per tutti i PID MVP;
- varia RPM, velocita, temperatura liquido, voltaggio ECU, carico motore e posizione acceleratore nel tempo;
- invia gli stessi eventi e log raw TX/RX del trasporto BLE reale.

La dashboard usa sempre `ObdTransport`, quindi funziona nello stesso modo in `Mock Adapter` e `Live Bluetooth`. Questa separazione e intenzionale: i futuri PID proprietari Jeep 4xe potranno essere aggiunti come profili/parser separati senza cambiare la UI o il client ELM327 di base.

## PID Lab read-only

La schermata `PID Lab` permette di inviare manualmente comandi OBD/ELM327 e salvare le risposte raw in un log esportabile:

- export CSV con timestamp, modalita adattatore, comando, risposta, flag standard e warning;
- export JSON con gli stessi campi;
- warning prima di inviare letture non standard, per esempio richieste `22....`;
- blocco dei servizi noti per scrittura, reset, security access, routine control, download/upload e codifica centralina.

Comandi standard ammessi senza warning:

- servizi OBD read-only `01`, `02`, `03`, `07`, `09`, `0A`;
- comandi ELM327 locali esplicitamente consentiti: `ATZ`, `ATI`, `ATRV`, `ATDP`, `ATDPN`, `AT@1`, `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATSP0`.

Servizi come `2E`, `2F`, `31`, `34`, `36`, `3B`, `27`, `10`, `11`, `14`, `28`, `85` sono bloccati. L'app non implementa programmazione centralina, codifiche, scritture DIDs, routine di calibrazione o security access.

## Piano evolutivo Jeep/ibrido

1. Stabilizzare BLE su adattatori noti, iniziando da Vgate iCar Pro 2S.
2. Aggiungere export dei log diagnostici e session replay per test automatici.
3. Introdurre una matrice di capability per ECU e protocolli OBD-II rilevati.
4. Popolare `CustomObdPid` solo con PID verificati e documentati internamente.
5. Separare parser/profili per 12V battery, DC/DC converter, HV battery, charging status, hybrid system e DTC.
6. Solo dopo logging e consenso esplicito, studiare PID Jeep/4xe e dati ibridi.
7. Tenere separati PID proprietari, profili veicolo e parser per evitare assunzioni fragili.

Non sono inclusi reverse engineering o PID proprietari Jeep/4xe in questo MVP.
