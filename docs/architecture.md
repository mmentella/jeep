# Architecture

## Process boundaries

`src/main` e il trusted Electron main process. Possiede SQLite, filesystem export e transport hardware. `src/preload` espone una API stretta con `contextBridge`. `src/renderer` e una UI React priva di Node integration e accesso hardware diretto.

## Core domain

`src/core` non dipende da Electron:

- `ObdTransport`: contratto raw request/response.
- `Elm327CommandQueue`: serializzazione FIFO e timeout.
- `Elm327FrameParser`: normalizzazione, frame CAN e errori tipizzati.
- `ObdValueParser`: formule PID standard.
- `ObdCommandPolicy`: allow, warning o block per PID Lab.
- `OBD_PIDS`: registry PID standard.
- `MockObdTransport`, `SerialObdTransport`, `BleObdTransport`: implementazioni sostituibili.

`SerialObdTransport` usa `serialport` nel main process. Elenca le porte COM, apre la porta selezionata, aggiunge `\r` al comando quando necessario e raccoglie chunk fino al prompt ELM327 `>`. Mantiene la risposta raw per logger e parser ed espone anche la variante con terminatori CR/LF normalizzati per diagnostica transport-level. Timeout, risposta parziale, porta assente, porta occupata e disconnect inatteso producono errori tipizzati.

`ObdService` possiede il transport attivo e ricrea la `Elm327CommandQueue` durante lo switch mock/serial. Il polling viene interrotto prima del disconnect; un solo polling puo essere in flight per evitare backlog sulla COM. Init, polling e PID Lab entrano sempre nella queue attiva.

## IPC

Il preload espone solo operazioni ristrette: stato adapter, elenco COM, connessione mock, connessione seriale, disconnect e invio manuale soggetto a policy. Il renderer non importa `serialport`, non apre porte e non invia byte direttamente all'hardware.

## Storage

`ObdSessionLogger` usa SQLite con `schema_version` e migrazione iniziale. Le tabelle sono `sessions`, `commands`, `responses`, `events` e `parsed_values`. Ogni comando viene registrato con source; ogni valore dashboard conserva anche la risposta raw.

## Safety

La policy viene applicata nel main process prima della queue. Il renderer non puo bypassarla. Sono bloccati servizi di reset, security access, routine control, write DID, I/O control, request download/upload e transfer. I servizi read-like proprietari richiedono conferma esplicita.
