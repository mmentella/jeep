# Jeep Renegade 4xe research workflow

## Metodo

1. Avvia una sessione e registra uno snapshot dei PID standard.
2. Annota stato del veicolo: quadro, ICE acceso o spento, SOC, temperatura, marcia e condizioni di sicurezza.
3. Invia dal PID Lab solo letture candidate verificate.
4. Esporta JSON o CSV e confronta sessioni con una sola variabile controllata.
5. Promuovi un PID proprietario nel registry solo dopo risultati ripetibili e formula documentata.

## Regole

- Non usare il laboratorio per coding, attuazioni o routine.
- Non inviare servizi bloccati aggirando la UI.
- Parti sempre da veicolo fermo e ambiente controllato.
- Conserva raw response, timestamp e condizioni di test.

## Setup hardware Windows

Per il Vgate reale su Windows usa il transport COM seriale quando l'adattatore espone Bluetooth Classic/SPP o USB seriale. Parti da `38400 baud`, esegui la baseline AT e `0100`, quindi verifica `0142` prima di avviare una raccolta.

Gli adattatori BLE-only richiedono un futuro transport GATT dedicato: non compaiono come COM e non sono supportati dal transport seriale. Procedura completa: [windows_serial_adapter_setup.md](windows_serial_adapter_setup.md).
