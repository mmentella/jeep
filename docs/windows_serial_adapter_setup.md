# Windows serial adapter setup

## Adattatori supportati

Il transport seriale di Jeep Notebook supporta adattatori ELM327 che Windows espone come porta COM:

- Vgate Bluetooth Classic con profilo SPP.
- Adattatori ELM327 USB seriali.

Un adattatore BLE-only non espone una porta COM. BLE usa caratteristiche GATT e richiede un transport diverso, non ancora implementato.

## Associare un Vgate Bluetooth Classic

1. Inserisci il Vgate nella presa OBD del veicolo.
2. Porta il quadro nello stato richiesto dal manuale dell'adattatore, con veicolo fermo e in condizioni sicure.
3. In Windows apri `Impostazioni > Bluetooth e dispositivi > Aggiungi dispositivo > Bluetooth`.
4. Seleziona il Vgate. Se Windows richiede un PIN, usa quello documentato dal produttore; valori comuni sono `1234` o `0000`, ma non assumerli se il manuale indica altro.
5. Attendi la conclusione dell'associazione.

## Trovare la porta COM

1. Apri `Gestione dispositivi`.
2. Espandi `Porte (COM e LPT)`.
3. Cerca la porta seriale Bluetooth associata al Vgate, ad esempio `COM7`.
4. Se Windows mostra una porta in ingresso e una in uscita per lo stesso dispositivo, prova prima quella in uscita.
5. In Jeep Notebook apri `Settings > Adapter`, premi `Refresh porte` e seleziona la stessa COM.

Chiudi terminali seriali o altre app diagnostiche prima di connettere Jeep Notebook: una COM normalmente puo essere aperta da un solo processo.

## Scegliere il baud rate

Parti da `38400 baud`, valore comune per adattatori ELM327 Bluetooth Classic. Se non ricevi risposta prova nell'ordine:

1. `9600 baud`
2. `115200 baud`

Il baud corretto dipende dal firmware dell'adattatore, non dal protocollo CAN del veicolo.

## Primo test

1. In `Settings > Adapter` seleziona COM e baud rate.
2. Premi `Connect`.
3. Apri `PID Lab`.
4. Invia questi comandi uno alla volta e controlla la risposta raw:

```text
ATZ
ATI
ATE0
ATL0
ATS0
ATH0
ATSP0
0100
0142
```

Risultati attesi:

- `ATZ` e `ATI`: identificazione firmware ELM327 o compatibile.
- `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATSP0`: `OK`.
- `0100`: bitmap PID supportati con risposta che inizia da `41 00`.
- `0142`: tensione ECU con risposta che inizia da `41 42`.

Jeep Notebook esegue gia la sequenza AT durante `Connect`. Ripeterla dal PID Lab e utile per la prima verifica controllata e per vedere il raw log SQLite.

## Nessuna risposta

Se non arriva il prompt `>` o la connessione fallisce:

1. Verifica che il Vgate sia alimentato e ancora associato a Windows.
2. Premi `Refresh porte` e verifica che la COM sia ancora presente.
3. Chiudi altre app che possono occupare la COM.
4. Prova `38400`, poi `9600`, poi `115200`.
5. Usa `Disconnect`, rimuovi e reinserisci l'adattatore, quindi riconnetti.
6. Controlla `Ultimo errore` in Settings e i log della sessione: timeout e disconnect conservano anche l'eventuale risposta parziale.
7. Se il dispositivo non compare mai come COM, verifica se il modello e BLE-only.

## Bluetooth Classic/SPP e BLE

Bluetooth Classic/SPP emula un collegamento seriale: Windows crea una COM e Jeep Notebook usa `SerialObdTransport`.

BLE non usa SPP e normalmente non crea una COM. Comunica tramite servizi e caratteristiche GATT; richiede `BleObdTransport`, che resta intenzionalmente fuori dallo scope attuale.
