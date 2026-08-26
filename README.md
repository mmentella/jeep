# Jeep Notebook

Console desktop Windows-first per diagnostica OBD, logging e reverse engineering read-only dei PID Jeep Renegade 4xe. La nuova app Electron sostituisce la UI iOS SwiftUI senza dipendere da macOS e conserva i concetti consolidati del prototipo: transport astratto, mock, command queue ELM327 seriale, parser robusto, errori tipizzati, PID standard, PID Lab, logging persistente e safety policy.

## Quick start Windows

Prerequisiti: Node.js 22 LTS e npm.

```powershell
npm install
npm run dev
```

`npm install` esegue automaticamente `electron-rebuild` per preparare `better-sqlite3` con l'ABI Electron corretta su Windows.

Verifica:

```powershell
npm test
npm run lint
npm run build
```

## MVP

- Electron main process per hardware, SQLite, filesystem export e IPC.
- React renderer con dashboard live, PID Lab, console raw, session browser, notebook e settings.
- Mock mode automatico con valori variabili realistici.
- SQLite in `%APPDATA%` tramite `app.getPath("userData")`.
- Export sessioni JSON, CSV e TXT.
- Transport COM seriale Windows reale per adattatori Bluetooth Classic/SPP e USB seriali.
- Placeholder isolato per BLE GATT Windows.
- Safety policy read-only applicata nel main process prima della queue.

I sorgenti Swift restano nel repository come riferimento storico. La codebase desktop vive in `src/`.

## Vgate reale su Windows

Per usare un Vgate Bluetooth Classic/SPP o un adattatore USB seriale:

1. Associa l'adattatore in Windows e individua la porta COM assegnata.
2. Avvia l'app, apri `Settings > Adapter`, premi `Refresh porte`, seleziona la COM e parti da `38400 baud`.
3. Premi `Connect`. Dashboard e PID Lab usano ora il transport seriale attraverso la command queue del main process.
4. Usa `Disconnect` prima di rimuovere l'adattatore. Puoi selezionare `Usa Mock` per tornare alla simulazione senza riavviare.

BLE GATT non e implementato: un adattatore BLE-only non espone una COM e non puo usare questo transport.

Dettagli: [docs/windows_serial_adapter_setup.md](docs/windows_serial_adapter_setup.md), [docs/architecture.md](docs/architecture.md), [docs/elm327_command_queue.md](docs/elm327_command_queue.md), [docs/jeep_4xe_research_workflow.md](docs/jeep_4xe_research_workflow.md).
