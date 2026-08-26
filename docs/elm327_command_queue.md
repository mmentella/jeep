# ELM327 command queue

`Elm327CommandQueue` e l'unico punto che invia comandi a un `ObdTransport`. Init, polling e PID Lab condividono la stessa coda FIFO per impedire scambi concorrenti sull'adattatore ELM327.

Flusso:

1. Il chiamante crea un comando con source, timeout e prefisso risposta opzionale.
2. La queue attende il completamento del comando precedente.
3. Il transport invia il comando e raccoglie dati fino al prompt `>`.
4. Il timeout abortisce l'operazione e libera la queue.
5. `Elm327FrameParser` normalizza raw text, classifica gli errori adattatore e produce frame tipizzati.
6. Il logger registra TX, RX o errore in SQLite.

Il transport seriale reale deve rispettare `AbortSignal`: un timeout non puo lasciare una lettura pendente capace di contaminare la risposta successiva.
