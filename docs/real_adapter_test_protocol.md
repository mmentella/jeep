# Primo test reale Vgate su Windows

Procedura guidata per il primo collegamento di Jeep Notebook a una Jeep
Renegade 4xe tramite adattatore Vgate ELM327 compatibile Bluetooth Classic/SPP.

Il test e' esclusivamente read-only. Non eseguire test in marcia e non inviare
comandi diversi da quelli elencati.

## Obiettivo

Confermare, in ordine:

1. stabilita della porta COM Windows;
2. handshake ELM327;
3. collegamento OBD standard con protocollo automatico;
4. lettura della tensione ECU `0142`;
5. logging ed export della sessione.

Il transport corrente richiede una porta COM. Un Vgate BLE-only non e'
supportato: BLE usa GATT e normalmente non crea una COM Windows.

## 1. Preparazione auto

1. Parcheggia l'auto in un luogo sicuro, ventilato e con spazio sufficiente.
2. Mantieni l'auto ferma per tutta la procedura.
3. Inserisci il freno a mano.
4. Seleziona `P` e non iniziare il test in marcia.
5. Collega il Vgate alla presa OBD con quadro spento, salvo indicazioni diverse
   del manuale dell'adattatore.
6. Per il pairing Bluetooth e il primo handshake porta il quadro nello stato
   richiesto dal Vgate. Se i PID non rispondono, usa lo stato `READY` mantenendo
   sempre `P` e freno a mano inserito.
7. Considera che in stato `READY` il motore termico puo' avviarsi
   automaticamente. Non eseguire la procedura in un ambiente chiuso.
8. Mantieni sotto controllo la batteria 12 V. Evita sessioni prolungate con
   quadro acceso e auto non in `READY`; interrompi il test se compaiono avvisi,
   tensioni anomale o comportamento instabile.
9. Non scollegare il Vgate durante uno scambio. Usa prima `Disconnect` in Jeep
   Notebook.

Annota prima del test:

```text
Data e ora:
Veicolo:
Stato veicolo: quadro acceso / READY
Motore termico: spento / acceso
Marcia: P
Freno a mano: inserito
SOC batteria trazione:
Temperatura esterna:
Note batteria 12 V:
Modello Vgate:
```

## 2. Preparazione Windows

### Pairing Bluetooth

1. Verifica che il Vgate sia alimentato dalla presa OBD.
2. Apri `Impostazioni > Bluetooth e dispositivi`.
3. Seleziona `Aggiungi dispositivo > Bluetooth`.
4. Seleziona il Vgate.
5. Se Windows richiede un PIN, usa quello indicato dal produttore. Valori
   comuni sono `1234` e `0000`, ma non assumerli se il manuale indica altro.
6. Attendi il completamento dell'associazione.

### Identificazione porta COM

1. Apri `Gestione dispositivi`.
2. Espandi `Porte (COM e LPT)`.
3. Individua la porta seriale Bluetooth del Vgate, per esempio `COM7`.
4. Se Windows espone una porta in ingresso e una in uscita, prova prima quella
   in uscita.
5. Annota la porta:

```text
Porta COM:
Tipo: uscita / ingresso / non indicato
```

Se non compare alcuna COM, vai a [Troubleshooting](#7-troubleshooting).

### Chiusura app concorrenti

Chiudi software diagnostici, terminali seriali, monitor COM e precedenti
istanze di Jeep Notebook. Una COM normalmente puo' essere aperta da un solo
processo.

### Scelta baud rate

Usa questo ordine:

1. `38400 baud`
2. `9600 baud` se `38400` non risponde
3. `115200 baud` se i primi due non rispondono

Il baud rate riguarda il collegamento seriale tra Windows e Vgate. Non e' il
baud rate del bus CAN dell'auto.

Annota:

```text
Baud rate provati:
Baud rate funzionante:
```

## 3. Connessione da Jeep Notebook

1. Avvia Jeep Notebook con `npm run dev` su una macchina fidata.
2. Non navigare siti web non fidati durante la sessione di sviluppo.
3. Apri `Settings > Adapter`.
4. Premi `Refresh porte`.
5. Seleziona la COM annotata e `38400 baud`.
6. Premi `Connect`.
7. Attendi lo stato `LIVE / SERIAL`.

Durante `Connect`, Jeep Notebook esegue gia' automaticamente:

```text
ATZ
ATI
ATE0
ATL0
ATS0
ATH0
ATSP0
```

Se `Connect` fallisce, consulta `Ultimo errore` in `Settings > Adapter` e vai a
[Troubleshooting](#7-troubleshooting). Se riesce, apri `PID Lab` e ripeti i
comandi uno alla volta per documentare il primo handshake manuale. Controlla la
risposta raw dopo ogni invio.

Il polling standard parte automaticamente dopo la connessione. I suoi scambi
possono comparire nel log insieme ai comandi manuali; la command queue li
serializza sulla COM.

## 4. Primo handshake ELM327

Invia i comandi nel `PID Lab` esattamente in questo ordine.

| Passo | Comando | Risposta attesa | Se restituisce errore | Se non risponde |
| ---: | --- | --- | --- | --- |
| 1 | `ATZ` | Banner firmware, per esempio `ELM327 v1.5`, seguito dal prompt `>` | Un testo illeggibile suggerisce baud errato; `?` suggerisce firmware incompatibile o comando non riconosciuto | Attendi il timeout, usa `Disconnect`, chiudi app concorrenti e riprova il baud successivo |
| 2 | `ATI` | Identificativo firmware ELM327 o compatibile, seguito da `>` | `?` indica comando non riconosciuto o clone non compatibile | Verifica alimentazione e stabilita COM; poi riconnetti |
| 3 | `ATE0` | `OK` | L'echo non e' stato disabilitato; il log restera' piu' rumoroso | Riconnetti e verifica baud rate |
| 4 | `ATL0` | `OK` | I linefeed potrebbero restare attivi; il parser puo' vedere righe aggiuntive | Riconnetti e verifica baud rate |
| 5 | `ATS0` | `OK` | Gli spazi potrebbero restare attivi; conserva il raw log | Riconnetti e verifica baud rate |
| 6 | `ATH0` | `OK` | Gli header CAN potrebbero restare visibili; conserva il raw log | Riconnetti e verifica baud rate |
| 7 | `ATSP0` | `OK` | Il Vgate non ha accettato la selezione protocollo automatica | Verifica stato quadro/`READY`, riconnetti e riprova |

Note:

- `ATZ` resetta l'interfaccia ELM327, non le ECU del veicolo.
- Il prompt `>` indica che l'adattatore e' pronto per il comando successivo.
- Dopo `ATE0`, non aspettarti piu' l'echo del comando nella risposta raw.
- Se nessun comando AT risponde, non procedere ai PID OBD.

Annota:

```text
ATZ:
ATI:
ATE0:
ATL0:
ATS0:
ATH0:
ATSP0:
```

## 5. Primo test OBD standard

Invia i comandi nel `PID Lab` nell'ordine indicato. Una risposta OBD positiva al
servizio `01` inizia con `41`. I byte dati sono indicati come `A`, `B`, `C` e
`D`.

| Passo | Comando | Lettura | Risposta attesa generica | Formula | Valore plausibile a veicolo fermo |
| ---: | --- | --- | --- | --- | --- |
| 1 | `0100` | PID supportati da `01` a `20` | `41 00 A B C D` | Bitmap a 32 bit: ogni bit impostato indica un PID supportato | Non e' un valore fisico. Deve arrivare una bitmap non vuota |
| 2 | `010C` | Regime motore | `41 0C A B` | RPM = `(256 * A + B) / 4` | `0 rpm` con termico spento; tipicamente circa `650-1000 rpm` al minimo se acceso |
| 3 | `010D` | Velocita veicolo | `41 0D A` | km/h = `A` | `0 km/h` |
| 4 | `0105` | Temperatura liquido refrigerante | `41 05 A` | gradi C = `A - 40` | A freddo vicina alla temperatura ambiente; a caldo tipicamente circa `70-110 C` |
| 5 | `0104` | Carico motore calcolato | `41 04 A` | percentuale = `A * 100 / 255` | Variabile; tipicamente bassa a veicolo fermo. Con termico spento puo' essere `0%` |
| 6 | `0111` | Posizione acceleratore | `41 11 A` | percentuale = `A * 100 / 255` | Tipicamente vicina a `0%` con pedale rilasciato |
| 7 | `0142` | Tensione modulo di controllo | `41 42 A B` | volt = `(256 * A + B) / 1000` | Indicativamente `12-15 V`; in `READY` il convertitore DC/DC puo' portarla verso `13.5-14.8 V` |

Valuta i valori nel contesto della Renegade 4xe: il motore termico puo' essere
spento anche quando l'auto e' pronta. Per il primo test conta prima di tutto la
presenza di risposte coerenti e stabili.

Se un PID restituisce `NO DATA`, annotalo e continua solo con gli altri PID
standard. Se `0100` o `0142` non rispondono, applica i criteri
[GO/NO-GO](#8-criteri-gono-go).

Annota:

```text
0100:
010C:
010D:
0105:
0104:
0111:
0142:
```

## 6. Logging ed export

### Sessione

Jeep Notebook crea automaticamente una sessione SQLite quando attiva il
transport seriale. Comandi di inizializzazione, polling, invii manuali, raw
response, timeout ed eventi vengono registrati.

1. Esegui il test senza rimuovere il Vgate.
2. Al termine apri `Settings > Adapter`.
3. Premi `Disconnect` per arrestare polling e chiudere correttamente la COM.
4. Apri `Session logs`.
5. Premi `Aggiorna`.
6. Seleziona la sessione appena conclusa, normalmente quella con ID piu' alto.

### Export

1. Nella sessione selezionata premi `JSON`, `CSV` o `TXT`.
2. Salva almeno `JSON` per conservare la struttura completa e `TXT` per una
   lettura rapida del raw log.
3. Usa `CSV` quando vuoi confrontare sessioni o importare dati in un foglio di
   calcolo.

L'app propone un nome simile a `jeep-notebook-session-12.json`. Per i file
salvati usa questa convenzione:

```text
YYYYMMDD_HHMM_Jeep4xe_Vgate_COMx_baud_stato_session-ID.ext
```

Esempio:

```text
20260602_1430_Jeep4xe_Vgate_COM7_38400_READY_session-12.json
```

Conserva accanto agli export le note compilate durante la procedura.

## 7. Troubleshooting

### COM non appare

1. Verifica che il Vgate sia alimentato.
2. Controlla il pairing in `Impostazioni > Bluetooth e dispositivi`.
3. Riapri `Gestione dispositivi > Porte (COM e LPT)`.
4. Rimuovi e ripeti il pairing se necessario.
5. Se compaiono due COM, prova prima quella in uscita.
6. Se non compare mai una COM, verifica che il Vgate supporti Bluetooth
   Classic/SPP. Un modello BLE-only non funziona con il transport corrente.

### Access denied o porta occupata

1. Premi `Disconnect` nelle altre istanze di Jeep Notebook.
2. Chiudi software diagnostici e terminali seriali.
3. Chiudi e riapri Jeep Notebook.
4. Se necessario, disattiva e riattiva il Bluetooth Windows.

### Timeout

1. Verifica che il Vgate sia alimentato e vicino al PC.
2. Usa `Disconnect`.
3. Prova `38400`, poi `9600`, poi `115200`.
4. Verifica quadro acceso o stato `READY`.
5. Rimuovi e reinserisci il Vgate solo dopo aver disconnesso l'app.
6. Interrompi se i timeout continuano: non compensare inviando comandi
   ripetutamente.

### `NO DATA`

`NO DATA` significa che l'ECU non ha restituito dati per quel PID. Non implica
necessariamente un guasto del Vgate.

1. Verifica prima che `0100` risponda.
2. Porta il veicolo nello stato `READY` se era solo a quadro acceso.
3. Annota quali PID restituiscono `NO DATA`.
4. Non insistere su PID non supportati.

### `UNABLE TO CONNECT`

L'ELM327 non e' riuscito a collegarsi alle ECU del veicolo.

1. Verifica quadro acceso o `READY`.
2. Ripeti `ATSP0`.
3. Usa `Disconnect`, riconnetti e riprova `0100`.
4. Se persiste, interrompi il test e conserva il log.

### Risposta con echo

Se la risposta include il comando inviato, per esempio `010C`, invia `ATE0`.
Se `ATE0` restituisce `OK` ma l'echo continua:

1. annota il comportamento;
2. usa `Disconnect`;
3. riconnetti;
4. verifica nuovamente l'handshake.

### Baud rate sbagliato

Sintomi tipici: nessuna risposta, caratteri illeggibili, timeout immediati o
risposte intermittenti.

1. Usa `Disconnect`.
2. Riprova nell'ordine `38400`, `9600`, `115200`.
3. Mantieni una sola app collegata alla COM.
4. Annota il primo baud rate stabile.

### Protocollo non trovato

Sintomi tipici: `UNABLE TO CONNECT`, `NO DATA` per tutti i PID o ricerca
protocollo senza esito.

1. Verifica stato `READY`.
2. Invia `ATSP0`.
3. Riprova `0100`.
4. Non forzare manualmente protocolli specifici durante il primo test.
5. Se `0100` continua a non rispondere, classifica la sessione `NO-GO`.

### Disconnect frequenti

1. Interrompi l'invio di comandi.
2. Premi `Disconnect` se il pulsante e' ancora disponibile.
3. Salva i log della sessione.
4. Verifica alimentazione Vgate, pairing Bluetooth e distanza dal PC.
5. Non proseguire il test reale finche' la COM non e' stabile.

## 8. Criteri GO/NO-GO

### GO

Il primo test e' `GO` solo se:

- `ATZ` risponde;
- `ATI` risponde;
- `0100` risponde con prefisso `41 00`;
- almeno `0142` risponde con prefisso `41 42`;
- la COM resta stabile durante handshake, letture ed export.

Gli altri PID standard possono essere annotati come supportati, `NO DATA` o da
verificare in una sessione successiva.

### NO-GO

Interrompi il test e classificalo `NO-GO` se:

- nessun comando AT risponde;
- la COM e' instabile;
- i timeout sono continui;
- avvengono disconnect frequenti;
- `0100` non risponde dopo riconnessione e verifica dello stato `READY`;
- compaiono avvisi del veicolo o tensione 12 V anomala.

Non passare a ricerca PID proprietari durante una sessione `NO-GO`.

## Checklist stampabile

```text
PRIMO TEST REALE VGATE - JEEP NOTEBOOK

Data e ora: ______________________
Operatore: _______________________
Modello Vgate: ___________________
Porta COM: _______________________
Baud rate: _______________________

PREPARAZIONE AUTO
[ ] Auto ferma in luogo sicuro e ventilato
[ ] Marcia P
[ ] Freno a mano inserito
[ ] Quadro acceso / READY annotato: __________________
[ ] Motore termico spento / acceso annotato: _________
[ ] Batteria 12 V sotto controllo
[ ] Nessun test in marcia

PREPARAZIONE WINDOWS
[ ] Pairing Bluetooth completato
[ ] Vgate Bluetooth Classic/SPP confermato
[ ] Porta COM identificata
[ ] App concorrenti e terminali seriali chiusi
[ ] Partenza da 38400 baud

CONNESSIONE
[ ] Settings > Adapter > Refresh porte
[ ] COM selezionata
[ ] Baud selezionato
[ ] Connect completato
[ ] Stato LIVE / SERIAL

HANDSHAKE MANUALE NEL PID LAB
[ ] ATZ   risposta: __________________________________
[ ] ATI   risposta: __________________________________
[ ] ATE0  OK
[ ] ATL0  OK
[ ] ATS0  OK
[ ] ATH0  OK
[ ] ATSP0 OK

PID STANDARD
[ ] 0100  risposta: __________________________________
[ ] 010C  RPM: _______________________________________
[ ] 010D  velocita: __________________________________
[ ] 0105  temperatura liquido: _______________________
[ ] 0104  carico motore: _____________________________
[ ] 0111  acceleratore: ______________________________
[ ] 0142  tensione ECU: ______________________________

STABILITA
[ ] Nessun timeout continuo
[ ] Nessun disconnect frequente
[ ] COM stabile
[ ] Nessun avviso anomalo del veicolo

CHIUSURA E LOGGING
[ ] Disconnect premuto prima di rimuovere il Vgate
[ ] Session logs > Aggiorna
[ ] Session ID annotato: _____________________________
[ ] Export JSON salvato
[ ] Export TXT salvato
[ ] Export CSV salvato se utile
[ ] Note veicolo conservate con gli export

ESITO
[ ] GO: ATZ, ATI, 0100 e 0142 rispondono; COM stabile
[ ] NO-GO: test interrotto e log conservato

Nome export:
______________________________________________________

Note:
______________________________________________________
______________________________________________________
______________________________________________________
```

