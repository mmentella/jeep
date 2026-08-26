import { useCallback, useEffect, useRef, useState } from 'react'
import type { LogEntry, ObdConnectionState, ObdReading, SerialPortInfo, SessionSummary } from '../../core/types'

type Page = 'dashboard' | 'lab' | 'console' | 'sessions' | 'notebook' | 'settings'
const pages: { id: Page; label: string; glyph: string }[] = [
  { id: 'dashboard', label: 'Dashboard live', glyph: '01' },
  { id: 'lab', label: 'PID Lab', glyph: '02' },
  { id: 'console', label: 'Console raw', glyph: '03' },
  { id: 'sessions', label: 'Session logs', glyph: '04' },
  { id: 'notebook', label: 'Notebook', glyph: '05' },
  { id: 'settings', label: 'Settings', glyph: '06' }
]

export function App(): JSX.Element {
  const [page, setPage] = useState<Page>('dashboard')
  const [connected, setConnected] = useState(false)
  const [adapterState, setAdapterState] = useState<ObdConnectionState>({ connected: false, mode: 'mock' })
  const [readings, setReadings] = useState<Record<string, ObdReading>>({})
  const [logs, setLogs] = useState<LogEntry[]>([])
  const [sessions, setSessions] = useState<SessionSummary[]>([])
  const [selectedSession, setSelectedSession] = useState<number>()
  const [command, setCommand] = useState('010C')
  const [labResult, setLabResult] = useState('')
  const [warning, setWarning] = useState('')
  const [error, setError] = useState('')
  const selectedSessionRef = useRef<number>()

  const api = window.jeepNotebook
  const refreshLogs = useCallback(async (id?: number) => setLogs(api ? await api.getLogs(id) : []), [api])
  const refreshSessions = useCallback(async () => setSessions(api ? await api.listSessions() : []), [api])

  useEffect(() => {
    if (!api) {
      setError('Web preview: il bridge Electron non e disponibile. Avvia con npm run dev per usare mock mode e SQLite.')
      return
    }
    const offReading = api.onReading((reading) => setReadings((current) => ({ ...current, [reading.pid]: reading })))
    const offState = api.onState((state) => { setConnected(state.connected); setAdapterState(state) })
    const offLogs = api.onLogs(() => void refreshLogs(selectedSessionRef.current))
    api.start().then(() => {
      setConnected(true)
      void api.getState().then(setAdapterState)
      void refreshSessions()
      void refreshLogs()
    }).catch((reason) => setError(String(reason)))
    return () => { offReading(); offState(); offLogs(); void api.stop() }
  }, [api, refreshLogs, refreshSessions])

  const send = async (confirmed = false): Promise<void> => {
    setError('')
    setWarning('')
    try {
      if (!api) throw new Error('PID Lab disponibile solo nella finestra Electron.')
      const response = await api.sendManual(command, confirmed)
      if (response.warning) setWarning(response.warning)
      else setLabResult(response.rawText)
      await refreshLogs(selectedSession)
      await refreshSessions()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    }
  }

  const selectSession = async (id?: number): Promise<void> => {
    setSelectedSession(id)
    selectedSessionRef.current = id
    await refreshLogs(id)
  }

  return (
    <main className="shell">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">JN</span><div><strong>Jeep Notebook</strong><small>4xe diagnostics lab</small></div></div>
        <nav>{pages.map((item) => <button className={page === item.id ? 'active' : ''} key={item.id} onClick={() => setPage(item.id)}><span>{item.glyph}</span>{item.label}</button>)}</nav>
        <div className="sidebar-footer"><span className={`dot ${connected ? 'online' : ''}`} />{connected ? `${adapterState.mode.toUpperCase()} adapter online` : 'Adapter offline'}</div>
      </aside>
      <section className="workspace">
        <header><div><p className="eyebrow">WINDOWS-FIRST OBD WORKSPACE</p><h1>{pages.find((item) => item.id === page)?.label}</h1></div><div className="status"><span className={`dot ${connected ? 'online' : ''}`} />{connected ? `LIVE / ${adapterState.mode.toUpperCase()}` : 'OFFLINE'}</div></header>
        {error && <div className="banner error">{error}</div>}
        {page === 'dashboard' && <Dashboard readings={readings} logs={logs} />}
        {page === 'lab' && <PidLab command={command} setCommand={setCommand} send={send} result={labResult} warning={warning} />}
        {page === 'console' && <RawConsole logs={logs} />}
        {page === 'sessions' && <Sessions sessions={sessions} logs={logs} selected={selectedSession} select={selectSession} refresh={refreshSessions} />}
        {page === 'notebook' && <Notebook />}
        {page === 'settings' && <Settings api={api} state={adapterState} setError={setError} />}
      </section>
    </main>
  )
}

function Dashboard({ readings, logs }: { readings: Record<string, ObdReading>; logs: LogEntry[] }): JSX.Element {
  const cards = [
    ['010C', 'RPM'], ['010D', 'Velocita'], ['0105', 'Temp. liquido'],
    ['0142', 'Voltaggio ECU'], ['0104', 'Carico motore'], ['0111', 'Acceleratore']
  ]
  return <><div className="metric-grid">{cards.map(([pid, title]) => <Metric key={pid} pid={pid} title={title} reading={readings[pid]} />)}</div><section className="panel"><PanelTitle title="Live activity" sub="Ultimi scambi serializzati dalla command queue" /><LogTable logs={logs.slice(-8)} /></section></>
}

function Metric({ pid, title, reading }: { pid: string; title: string; reading?: ObdReading }): JSX.Element {
  return <article className="metric"><div><span className="chip">{pid}</span><small>{title}</small></div><strong>{reading ? formatValue(reading.value) : '--'}</strong><em>{reading?.unit ?? 'waiting'}</em></article>
}

function PidLab({ command, setCommand, send, result, warning }: { command: string; setCommand(value: string): void; send(confirmed?: boolean): void; result: string; warning: string }): JSX.Element {
  return <div className="two-columns"><section className="panel"><PanelTitle title="Read-only command bench" sub="I comandi passano sempre da policy, queue e logger" /><label>ELM327 / OBD command</label><div className="command-row"><input value={command} onChange={(event) => setCommand(event.target.value)} placeholder="010C" /><button className="primary" onClick={() => send()}>Invia lettura</button></div>{warning && <div className="banner warning">{warning}<button onClick={() => send(true)}>Conferma lettura non standard</button></div>}<label>Raw response</label><pre>{result || 'Nessuna risposta ancora.'}</pre></section><section className="panel"><PanelTitle title="Safety policy" sub="Blocco applicato nel main process" /><ul className="policy"><li>Consentiti: PID standard read-only e AT allowlist.</li><li>Con conferma: letture proprietarie `18`, `19`, `22`.</li><li>Bloccati: reset, security access, routine control, write DID, I/O control, download e upload.</li></ul></section></div>
}

function RawConsole({ logs }: { logs: LogEntry[] }): JSX.Element {
  return <section className="panel"><PanelTitle title="Diagnostic console" sub="Raw TX/RX persistenti della sessione corrente" /><div className="terminal">{logs.map((log) => <div key={`${log.direction}-${log.id}-${log.timestamp}`}><time>{log.timestamp.slice(11, 23)}</time><b className={log.direction.toLowerCase()}>{log.direction}</b><code>{log.payload}</code></div>)}</div></section>
}

function Sessions({ sessions, logs, selected, select, refresh }: { sessions: SessionSummary[]; logs: LogEntry[]; selected?: number; select(id?: number): void; refresh(): void }): JSX.Element {
  const active = selected ?? sessions[0]?.id
  const exportCurrent = (format: 'json' | 'csv' | 'txt'): void => { if (active) void window.jeepNotebook?.exportSession(active, format) }
  return <div className="two-columns sessions"><section className="panel"><PanelTitle title="Session browser" sub="SQLite persistent history" /><button className="quiet" onClick={() => refresh()}>Aggiorna</button>{sessions.map((session) => <button className={`session ${active === session.id ? 'selected' : ''}`} key={session.id} onClick={() => select(session.id)}><b>Session #{session.id}</b><small>{new Date(session.startedAt).toLocaleString()} · {session.commandCount} commands</small></button>)}</section><section className="panel"><PanelTitle title={`Session #${active ?? '-'}`} sub="Export report raw" /><div className="export-row"><button onClick={() => exportCurrent('json')}>JSON</button><button onClick={() => exportCurrent('csv')}>CSV</button><button onClick={() => exportCurrent('txt')}>TXT</button></div><LogTable logs={logs} /></section></div>
}

function Notebook(): JSX.Element {
  return <div className="notebook-grid"><section className="panel note"><span className="chip">WORKFLOW</span><h2>Jeep Renegade 4xe research</h2><p>Usa il PID Lab per esplorare letture candidate, conserva raw response e condizioni del veicolo, poi promuovi solo PID ripetibili nel registry verificato.</p></section><section className="panel note"><span className="chip">BASELINE</span><h2>Standard OBD snapshot</h2><p>RPM, velocita, coolant, voltage, engine load e throttle sono acquisiti continuamente in mock mode e persistiti nella sessione SQLite.</p></section><section className="panel note"><span className="chip">NEXT</span><h2>Vgate on Windows</h2><p>Collega un transport COM seriale o BLE GATT nel main process. Renderer, policy, parser, queue e logger restano invariati.</p></section></div>
}

function Settings({ api, state, setError }: { api?: Window['jeepNotebook']; state: ObdConnectionState; setError(value: string): void }): JSX.Element {
  const [ports, setPorts] = useState<SerialPortInfo[]>([])
  const [portPath, setPortPath] = useState('')
  const [baudRate, setBaudRate] = useState(38400)
  const [loading, setLoading] = useState(false)

  const run = async (operation: () => Promise<void>): Promise<void> => {
    setLoading(true)
    setError('')
    try { await operation() } catch (reason) { setError(reason instanceof Error ? reason.message : String(reason)) } finally { setLoading(false) }
  }
  const refreshPorts = useCallback(async (): Promise<void> => {
    if (!api) return
    setLoading(true)
    setError('')
    try {
      const available = await api.listSerialPorts()
      setPorts(available)
      setPortPath((current) => available.some((port) => port.path === current) ? current : available[0]?.path ?? '')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason))
    } finally {
      setLoading(false)
    }
  }, [api, setError])
  useEffect(() => { void refreshPorts() }, [refreshPorts])

  return <section className="panel settings"><PanelTitle title="Adapter" sub="Hardware access isolato nel main process Electron" />
    <div className="adapter-status"><b>Stato: {state.connected ? `connesso via ${state.mode.toUpperCase()}` : 'disconnesso'}</b>{state.portPath && <small>{state.portPath} @ {state.baudRate} baud</small>}{state.lastError && <small className="last-error">Ultimo errore: {state.lastError}</small>}</div>
    <div className="setting"><div><b>Mock ELM327</b><small>Simulazione realistica senza hardware</small></div><button disabled={loading || state.connected && state.mode === 'mock'} onClick={() => void run(() => api?.connectMock() ?? Promise.resolve())}>{state.connected && state.mode === 'mock' ? 'Attivo' : 'Usa Mock'}</button></div>
    <div className="setting serial-setting"><div><b>Serial COM</b><small>Bluetooth Classic/SPP o adattatore USB seriale Windows</small></div><div className="serial-controls"><select value={portPath} onChange={(event) => setPortPath(event.target.value)} disabled={loading}>{ports.length ? ports.map((port) => <option key={port.path} value={port.path}>{port.path}{port.manufacturer ? ` - ${port.manufacturer}` : ''}</option>) : <option value="">Nessuna porta COM</option>}</select><select value={baudRate} onChange={(event) => setBaudRate(Number(event.target.value))} disabled={loading}>{[38400, 9600, 115200].map((rate) => <option key={rate} value={rate}>{rate} baud</option>)}</select><button onClick={() => void refreshPorts()} disabled={loading}>Refresh porte</button><button className="primary" disabled={loading || !portPath || state.connected && state.mode === 'serial'} onClick={() => void run(() => api?.connectSerial(portPath, baudRate) ?? Promise.resolve())}>Connect</button></div></div>
    <div className="setting"><div><b>Connessione attiva</b><small>Interrompe polling e chiude la porta in modo pulito</small></div><button disabled={loading || !state.connected} onClick={() => void run(() => api?.stop() ?? Promise.resolve())}>Disconnect</button></div>
    <div className="setting disabled"><div><b>BLE GATT</b><small>Non implementato: usare solo con adattatori BLE dedicati</small></div><span>planned</span></div>
  </section>
}

function PanelTitle({ title, sub }: { title: string; sub: string }): JSX.Element { return <div className="panel-title"><h2>{title}</h2><small>{sub}</small></div> }
function LogTable({ logs }: { logs: LogEntry[] }): JSX.Element { return <div className="log-table">{logs.map((log) => <div key={`${log.direction}-${log.id}-${log.timestamp}`}><time>{log.timestamp.slice(11, 19)}</time><b className={log.direction.toLowerCase()}>{log.direction}</b><code>{log.payload.replace(/\r?>/g, ' >')}</code></div>)}</div> }
function formatValue(value: number): string { return Math.abs(value) >= 100 ? value.toFixed(0) : value.toFixed(1) }
