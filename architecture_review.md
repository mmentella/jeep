# Architecture Review

## Executive Summary

Il progetto e una buona base MVP: separa trasporto, client ELM327, PID standard, parser, mock adapter, dashboard e PID Lab. Per una prima app SwiftUI e gia oltre il classico prototipo monolitico.

La criticita principale e che l'orchestrazione applicativa vive quasi tutta in `ObdDashboardViewModel`: connessione, polling, PID Lab, export, log, stato UI e dependency injection. Questo va bene per arrivare alla prima demo, ma diventera il collo di bottiglia appena entrano PID Jeep/4xe, profili veicolo, riconnessione, scheduler e logging persistente.

## P0 Hardening Implemented

Il P0 hardening ha chiuso il rischio principale della review: concorrenza fra polling automatico e PID Lab sul singolo canale ELM327.

Implementato:

- `Elm327CommandQueue` come actor seriale: un solo comando in-flight.
- `Elm327Command` con command string, timeout, expected response prefix opzionale e source.
- `Elm327FrameParser` con raw text, normalized text, linee, frame e prompt flag.
- `Elm327Error` tipizzato per `NO DATA`, `STOPPED`, `BUS ERROR`, `CAN ERROR`, `UNABLE TO CONNECT`, timeout, negative response e malformed frame.
- `ObdPollingScheduler` separato dal ViewModel.
- `ObdConnectionState` esplicito per idle/scanning/connecting/initializing/ready/disconnected/failed.
- PID Lab: sospende polling, usa la stessa queue, registra raw response, poi riprende polling.
- Test unitari per parser frame e command queue.

Vincoli mantenuti:

- nessun PID Jeep/4xe implementato;
- nessun comando di scrittura o programmazione centralina;
- compatibilita Mock Mode mantenuta;
- transport BLE/mock separati dal protocollo ELM327;
- nessun accesso applicativo diretto a `ObdTransport.send(_:)` fuori da `Elm327CommandQueue`.

## Architecture

### Strengths

- `ObdTransport` isola Bluetooth reale e mock. Questo e il punto architetturale piu sano del progetto.
- `Elm327Client` incapsula inizializzazione e invio comandi.
- `ObdPid` e `ObdValueParser` tengono i PID standard fuori dalla UI.
- `CustomObdPid` introduce il vocabolario giusto per futuri PID proprietari senza implementarli.
- `ObdCommandPolicy` e separato dalla UI, quindi puo essere testato e reso piu severo senza toccare `PidLabView`.
- I test coprono parser e policy, cioe le due parti piu facili da rompere senza accorgersene.

### Weaknesses

- `ObdDashboardViewModel` e troppo ampio: contiene stato connessione, polling, PID Lab, export, scelta adattatore e log diagnostico.
- `Elm327Client` e ancora sottile: non modella sessione, prompt, protocollo selezionato, retry, adattatore, echo, header, flow control o errori ELM327 tipizzati.
- `ObdTransport.send(_:)` forza una semantica request/response singola. E comoda per MVP, ma non rappresenta bene stream BLE, risposte multilinea, frammentazione e notifiche asincrone.
- `CustomObdPid.formula` e una stringa libera. Serve per catalogare, ma non e ancora eseguibile ne validabile.
- Non esiste un concetto di `VehicleProfile` o `PidCatalog` versionato.
- Non esiste persistenza di configurazione, sessioni, log diagnostici o preferenze.

## Responsibility Separation

Separazione attuale:

- Bluetooth: `BleObdTransport`
- mock: `MockObdTransport`
- ELM327: `Elm327Client`
- PID standard: `ObdPid`
- parsing: `ObdValueParser`
- sicurezza manual commands: `ObdCommandPolicy`
- UI/orchestrazione: `ObdDashboardViewModel`

La separazione e buona in orizzontale, ma manca un layer di use case/application service. In pratica il ViewModel fa anche da `ConnectionCoordinator`, `PollingService`, `PidLabService` e `LogStore`.

Raccomandazione:

- introdurre `ObdSession` per stato connessione + client ELM327;
- introdurre `ObdPollingEngine` per scheduling PID;
- introdurre `PidLabService` per validazione, invio manuale e log;
- introdurre `DiagnosticLogStore` per log ring-buffer + export;
- lasciare al ViewModel solo mapping stato-domain verso SwiftUI.

## Testability

Buona:

- `ObdTransport` permette mock e test di integrazione senza BLE.
- parser e command policy sono puri e testabili.
- mock mode esercita dashboard e log senza hardware.

Da migliorare:

- `MockObdTransport` usa `Date()` e `Double.random`, quindi non e deterministico per test.
- `ObdDashboardViewModel` non riceve clock/scheduler/log store in injection.
- `BleObdTransport` non e testabile senza CoreBluetooth reale o wrapper.
- `Elm327Client.initialize()` ha sleep fisso e non e parametrico.
- Non ci sono test su polling, PID Lab, export CSV/JSON, o flusso connect-initialize-poll.

## Dependency Injection

Il progetto usa una factory `AdapterMode -> ObdTransport`, buona per MVP.

Limiti:

- la factory e nel ViewModel, non in un composition root dedicato;
- `Elm327Client` viene creato internamente al ViewModel, quindi non e sostituibile direttamente;
- scheduler, clock, timeout, logger e parser non sono iniettati.

Raccomandazione:

- definire `ObdClientProtocol`;
- passare `ObdSessionFactory`;
- introdurre `Clock`/`Sleeper` astratto per test;
- separare `TransportFactory` da `AppEnvironment`.

## Jeep Proprietary PID Extensibility

La direzione e corretta: `CustomObdPid` contiene `id`, `name`, `request`, `expectedResponsePrefix`, `formula`, `unit`, `category`.

Mancano pero:

- protocollo formula sicuro: expression engine limitato o parser dichiarativo;
- gestione DID UDS `22` con header ECU, target address, response pending `7F xx 78`;
- profili veicolo: Jeep Renegade 4xe, Compass 4xe, model year, ECU variants;
- capability discovery;
- unit conversion e scaling versionati;
- metadata su sicurezza: read-only, requires ignition, requires ready mode, requires charging, experimental.

Per evitare caos futuro, i PID proprietari dovrebbero entrare come dati versionati, non come `switch` sparsi nel codice.

## Android Extensibility

L'architettura attuale e iOS-only per UI e BLE, ma il domain layer e quasi portabile concettualmente.

Portabile:

- PID definitions;
- ELM327 command sequencing;
- parser;
- command policy;
- log model;
- mock adapter behavior.

Non portabile:

- SwiftUI views;
- CoreBluetooth;
- `ShareLink`/Transferable;
- Xcode project.

Strategia Android:

- estrarre specifiche protocollo in documenti JSON/YAML: standard PID, custom PID, formula, category, safety policy;
- mantenere test vectors ELM327 in file condivisi;
- su Android implementare transport separati: BLE GATT, Bluetooth Classic SPP, Wi-Fi TCP;
- evitare di nascondere tutto dietro un solo transport se Android supporta Classic SPP e iOS no.

## Bluetooth Review

Apple documenta Core Bluetooth come framework per comunicare con dispositivi BLE e, in ambiti specifici, BR/EDR; per accessori Classic generici spesso serve MFi/External Accessory, mentre gli scanner OBD BLE usano GATT-like UART. Fonti: Apple Core Bluetooth docs e pagina Bluetooth Apple Developer.

Rischi principali:

- scansione senza service UUID trova troppo rumore;
- scelta characteristic per property e non per UUID puo selezionare la caratteristica sbagliata su adattatori complessi;
- non si aspetta esplicitamente `didUpdateNotificationState`;
- non si gestisce MTU/chunking in scrittura;
- non c'e serializzazione robusta delle richieste concorrenti;
- timeout fisso a 4s;
- nessun reconnect/backoff;
- nessun watchdog su connessione silenziosa;
- nessuna state restoration/background mode;
- `PendingResponse` supporta una sola richiesta e puo essere sovrascritto se `send` viene chiamato in parallelo.

### Vgate iCar Pro 2S

Il sito Vgate descrive iCar Pro 2S come adattatore Bluetooth OBD-II per iOS/Android/Windows. Manuali pubblici per varianti iCar Pro 2S indicano inoltre che su iOS l'utente non sempre deve cercare il device nella schermata Bluetooth di sistema, ma selezionarlo dall'app OBD. Questo e coerente con BLE/GATT e non con pairing Classic tradizionale.

Problemi attesi:

- varianti hardware/firmware diverse sotto nomi simili;
- alcuni modelli sono Bluetooth Classic, altri BLE, altri dual-mode;
- device name instabile o assente;
- UUID custom non documentati;
- risposte frammentate in piu notify;
- adattatori clone che rispondono `OK` a comandi non realmente supportati;
- `NO DATA`, `UNABLE TO CONNECT`, `CAN ERROR`, `BUS ERROR` anche dopo connessione BLE riuscita.

### BLE vs Bluetooth Classic

- BLE: visibile via CoreBluetooth, GATT services/characteristics, niente pairing SPP classico.
- Classic SPP: tipico ELM327 economico Android, non accessibile liberamente da app iOS generiche.
- iOS: per molti accessori Classic serve MFi/External Accessory o profili supportati da Apple.
- Android: puo supportare BLE e Classic SPP, quindi il futuro client Android dovrebbe avere piu transport.

## ELM327 Review

### Current Strengths

- inizializzazione minima `ATZ`, `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATSP0`;
- prompt `>` usato come delimitatore;
- parser ignora `SEARCHING...`;
- gestisce `NO DATA`;
- considera `STOPPED`, `UNABLE TO CONNECT`, `?`, `7F` come risposta negativa;
- parser accetta formato compatto e con header CAN 11-bit separato.

### Gaps

- `BUS ERROR`, `CAN ERROR`, `BUS INIT: ERROR`, `BUFFER FULL`, `RX ERROR` non sono classificati.
- `7F` viene cercato come substring: rischia falsi positivi in payload legittimi.
- non gestisce `7F xx 78` response pending con retry.
- non gestisce multilinea CAN multi-frame o piu ECU che rispondono allo stesso PID.
- non supporta header `7E8`/`7E9` multipli con scelta ECU.
- non gestisce echo se `ATE0` fallisce.
- non gestisce `>` mancante con risposta parziale.
- non ha un parser di frame ELM separato dal parser di valore PID.

Raccomandazione: creare un `Elm327ResponseParser` che produca un modello intermedio:

- `promptSeen`;
- `lines`;
- `frames`;
- `adapterError`;
- `ecuNegativeResponse`;
- `payloadCandidates`;
- `raw`.

`ObdValueParser` dovrebbe consumare solo payload gia normalizzati.

## Performance

Polling attuale: 6 PID, 120 ms fra PID, 600 ms fra cicli. In condizioni ideali significa un ciclo ogni circa 1.3s piu latenza adattatore/ECU. Per dashboard MVP va bene.

Rischi:

- su adattatori lenti il ciclo si allunga molto;
- ogni timeout costa 4s e blocca la catena;
- poll continuo anche con UI non visibile;
- nessun adaptive polling;
- nessun grouping PID;
- nessuna priorita fra RPM/speed e valori lenti come coolant/voltage;
- impatto su batteria telefono se BLE resta attivo e lo schermo rimane acceso;
- impatto su batteria auto se l'adattatore resta alimentato a veicolo spento.

Strategia consigliata:

- fast lane: RPM, speed, throttle a 2-5 Hz solo a dashboard visibile;
- medium lane: load, voltage a 1 Hz;
- slow lane: coolant, DTC, supported PIDs a 0.2-0.5 Hz;
- pause automatico se app in background;
- stop polling su veicolo spento o tensione bassa;
- reconnect/backoff invece di retry serrato.

## UI/UX Review

La UI e pulita, scura e gia leggibile. Per MVP va bene, ma non e ancora al livello di una alternativa a Car Scanner.

Rispetto a Car Scanner mancano:

- layout dashboard configurabile;
- grafici storici;
- scelta sensori;
- DTC e freeze frame;
- profili veicolo;
- registrazione viaggi;
- alert soglia;
- export sessione;
- onboarding adattatore;
- indicatori di qualita connessione.

Punti ancora brutti:

- troppe card uguali, poca gerarchia visiva;
- `PID Lab` e pericolosamente accessibile nella tab principale;
- stato connessione minimale;
- manca onboarding chiaro per BLE vs Classic;
- manca modalita "driving safe" con font grandi e pochi dati;
- manca landscape dashboard ottimizzata;
- i log raw sono utili ma non filtrabili.

Per uso durante guida:

- evitare input manuale mentre l'auto e in movimento;
- creare dashboard a massimo 3-4 valori grandi;
- contrasto alto, touch target grandi;
- niente scroll necessario per valori critici;
- supporto landscape;
- alert visivi sobri, non invasivi.

## Sources

- Apple Core Bluetooth documentation: https://developer.apple.com/documentation/corebluetooth
- Apple Bluetooth developer page: https://developer.apple.com/bluetooth/
- Apple Core Bluetooth background guide: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- Vgate iCar Pro 2S product page: https://www.vgatemall.com/products-detail/i-80/?s=2
- ELM327 datasheet mirror: https://cdn.sparkfun.com/assets/learn_tutorials/8/3/ELM327DS.pdf
