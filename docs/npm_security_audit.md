# npm security audit

Data audit: 2026-06-02

## Scopo

Audit diagnostico dopo l'introduzione di `serialport@^13.0.0`. Non sono stati
eseguiti fix automatici e non sono state modificate le dipendenze.

Comandi eseguiti:

```text
npm audit
npm audit --omit=dev
npm ls --all
```

Sono stati inoltre usati `npm ls --omit=dev --all`, `npm explain` e una ricerca
nel codice Electron per classificare l'impatto runtime.

## Risultato sintetico

| Audit | Moderate | High | Critical | Totale |
| --- | ---: | ---: | ---: | ---: |
| `npm audit` | 5 | 1 | 1 | 7 |
| `npm audit --omit=dev` | 0 | 0 | 0 | 0 |

`serialport@13.0.0` e il suo albero production non risultano vulnerabili.
L'introduzione di SerialPort ha reso visibile l'audit durante `npm install`, ma
non e' la sorgente dei 7 finding.

## Dipendenze production

`npm ls --omit=dev --all` include:

```text
jeep-notebook
+-- better-sqlite3@11.10.0
+-- react@18.3.1
+-- react-dom@18.3.1
`-- serialport@13.0.0
```

Non risultano advisory nell'albero production.

## Lista vulnerabilita

`npm audit` aggrega gli advisory in 7 nodi vulnerabili:

| Pacchetto vulnerabile | Versione installata | Severita npm | Sorgente / dependency chain | Runtime o dev tooling | Possibile fix sicuro | Rischio breaking change | Raccomandazione |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `electron` | `33.4.11` | high | root devDependency -> `electron` | **Runtime Electron** anche se npm lo classifica `dev`: il binario esegue l'app distribuita | Analizzare e testare l'upgrade a `electron@42.3.1` indicato da npm; non applicarlo automaticamente | **Alto**: salto major `33 -> 42`, rebuild moduli nativi e regression test richiesti | **fix now** in attivita dedicata prima di distribuire l'app; non blocca un test locale controllato |
| `electron-vite` | `2.3.0` | moderate | root devDependency -> `electron-vite` -> `esbuild@0.21.5`; root devDependency -> `electron-vite` -> `vite@5.4.21` | Solo build/dev tooling; non incluso nel runtime pacchettizzato | Valutare upgrade coordinato a `electron-vite@5.0.0` indicato da npm | **Alto**: salto major `2 -> 5` e migrazione toolchain | **defer**; pianificare upgrade toolchain |
| `esbuild` | `0.21.5` | moderate | root -> `electron-vite@2.3.0` -> `esbuild`; root -> `vite@5.4.21` -> `esbuild` | Solo dev server/build tooling | Versione non vulnerabile `>0.24.2`; usare una versione supportata dalle release aggiornate di Vite/electron-vite, senza override non testati | **Medio/alto**: fix coordinato con toolchain | **ignore perche dev-only** durante test locale; limitare il dev server a un ambiente fidato |
| `vite` | `5.4.21` | moderate | root devDependency -> `vite`; root -> `electron-vite` -> `vite`; root -> `vitest` -> `vite` | Solo dev server/build/test tooling | Advisory risolto oltre `6.4.1`; npm propone `vite@8.0.16`. Valutare migrazione coordinata | **Alto**: salto major e compatibilita con `electron-vite@2.3.0` da verificare | **defer**; non usare il dev server su reti o sessioni browser non fidate |
| `@vitest/mocker` | `2.1.9` | moderate | root -> `vitest@2.1.9` -> `@vitest/mocker` -> `vite` | Solo test tooling | Upgrade coordinato a `vitest@4.1.8` indicato da npm | **Alto**: salto major `2 -> 4` | **ignore perche dev-only** |
| `vite-node` | `2.1.9` | moderate | root -> `vitest@2.1.9` -> `vite-node` -> `vite` | Solo test tooling | Upgrade coordinato a `vitest@4.1.8` indicato da npm | **Alto**: salto major `2 -> 4` | **ignore perche dev-only** |
| `vitest` | `2.1.9` | critical | root devDependency -> `vitest` | Solo test tooling. L'advisory critico richiede Vitest UI server in ascolto; `package.json` usa `vitest run` e `@vitest/ui` non e' installato | Upgrade a `vitest@4.1.8` indicato da npm, con verifica test suite | **Alto**: salto major `2 -> 4` | **ignore perche dev-only** per il test adattatore; aggiornare in manutenzione toolchain |

## Advisory diretti

### Electron runtime

`electron@33.4.11` e' affetto dai seguenti advisory riportati da npm:

| Severita | Advisory | Nota di applicabilita a Jeep Notebook |
| --- | --- | --- |
| moderate | [GHSA-vmqv-hx8q-j7mg](https://github.com/advisories/GHSA-vmqv-hx8q-j7mg) - ASAR integrity bypass | Rilevante per distribuzione pacchettizzata se si fa affidamento su ASAR integrity |
| moderate | [GHSA-5rqw-r77c-jp79](https://github.com/advisories/GHSA-5rqw-r77c-jp79) - AppleScript injection in `app.moveToApplicationsFolder` | Non applicabile al test Windows; API non usata |
| moderate | [GHSA-xj5x-m3f3-5x3h](https://github.com/advisories/GHSA-xj5x-m3f3-5x3h) - service worker spoofing di reply `executeJavaScript` | Potenzialmente rilevante: l'app usa `webContents.executeJavaScript`, ma carica contenuto locale fidato |
| moderate | [GHSA-r5p7-gp4j-qhrx](https://github.com/advisories/GHSA-r5p7-gp4j-qhrx) - origin errata per permission request iframe | API non configurata nel progetto |
| moderate | [GHSA-3c8v-cfp5-9885](https://github.com/advisories/GHSA-3c8v-cfp5-9885) - out-of-bounds read in second-instance IPC | Non applicabile a Windows; gestione second-instance non usata |
| moderate | [GHSA-xwr5-m59h-vwqr](https://github.com/advisories/GHSA-xwr5-m59h-vwqr) - scope errato di `nodeIntegrationInWorker` | Mitigato: `nodeIntegration: false`, sandbox attiva |
| high | [GHSA-532v-xpq5-8h95](https://github.com/advisories/GHSA-532v-xpq5-8h95) - use-after-free offscreen paint callback | Offscreen rendering non usato |
| moderate | [GHSA-mwmh-mq4g-g6gr](https://github.com/advisories/GHSA-mwmh-mq4g-g6gr) - registry path injection in `setAsDefaultProtocolClient` | API non usata |
| moderate | [GHSA-9w97-2464-8783](https://github.com/advisories/GHSA-9w97-2464-8783) - use-after-free download save dialog | Download flow non usato |
| high | [GHSA-8337-3p73-46f4](https://github.com/advisories/GHSA-8337-3p73-46f4) - use-after-free in permission callbacks | Permission callbacks non configurate |
| high | [GHSA-jjp3-mq3x-295m](https://github.com/advisories/GHSA-jjp3-mq3x-295m) - use-after-free in PowerMonitor | API non usata |
| low | [GHSA-jfqx-fxh3-c62j](https://github.com/advisories/GHSA-jfqx-fxh3-c62j) - unquoted executable path in `setLoginItemSettings` | API non usata |
| moderate | [GHSA-4p4r-m79c-wq3v](https://github.com/advisories/GHSA-4p4r-m79c-wq3v) - header injection in protocol handlers e `webRequest` | API non usate |
| low | [GHSA-9899-m83m-qhpj](https://github.com/advisories/GHSA-9899-m83m-qhpj) - USB device selection validation | API non usata; SerialPort usa COM, non WebUSB |
| low | [GHSA-8x5q-pvf5-64mp](https://github.com/advisories/GHSA-8x5q-pvf5-64mp) - use-after-free offscreen shared texture callback | Offscreen rendering non usato |
| low | [GHSA-f37v-82c4-4x64](https://github.com/advisories/GHSA-f37v-82c4-4x64) - crash in `clipboard.readImage()` | API non usata |
| moderate | [GHSA-f3pv-wv63-48x8](https://github.com/advisories/GHSA-f3pv-wv63-48x8) - named `window.open` target scope | `window.open` non usato |
| high | [GHSA-9wfr-w7mm-pc7f](https://github.com/advisories/GHSA-9wfr-w7mm-pc7f) - renderer command-line switch injection | Web preference vulnerabile non usata |

La configurazione attuale riduce l'esposizione: `contextIsolation: true`,
`nodeIntegration: false` e `sandbox: true`. Queste mitigazioni non sostituiscono
l'upgrade Electron prima di una release.

### Dev server e test tooling

| Severita | Pacchetto | Advisory | Applicabilita |
| --- | --- | --- | --- |
| moderate | `esbuild@0.21.5` | [GHSA-67mh-4wv8-2f99](https://github.com/advisories/GHSA-67mh-4wv8-2f99) - siti web possono inviare richieste al development server e leggerne la risposta | Solo dev server; evitare navigazione web non fidata durante `npm run dev` |
| moderate | `vite@5.4.21` | [GHSA-4w7w-66w2-5vf9](https://github.com/advisories/GHSA-4w7w-66w2-5vf9) - path traversal nella gestione `.map` delle optimized deps | Solo dev server |
| critical | `vitest@2.1.9` | [GHSA-5xrq-8626-4rwp](https://github.com/advisories/GHSA-5xrq-8626-4rwp) - lettura ed esecuzione file arbitrari quando Vitest UI server e' in ascolto | Non attivo nello script corrente `vitest run`; `@vitest/ui` non installato |

## Valutazione test adattatore reale

Il test locale dell'adattatore seriale puo' procedere con queste condizioni:

1. Usare una macchina di sviluppo fidata.
2. Non esporre il dev server sulla rete.
3. Non navigare siti non fidati durante `npm run dev`.
4. Non distribuire questa build Electron come release.
5. Pianificare separatamente l'upgrade Electron con rebuild di
   `better-sqlite3` e regression test.

## Verdetto

**SAFE TO REAL ADAPTER TEST**

