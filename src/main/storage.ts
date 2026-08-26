import Database from 'better-sqlite3'
import type { LogEntry, ObdReading, SessionSummary } from '../core/types'

export class ObdSessionLogger {
  private readonly db: Database.Database
  private sessionId?: number

  constructor(path: string) {
    this.db = new Database(path)
    this.db.pragma('journal_mode = WAL')
    this.migrate()
  }

  startSession(mode: string): number {
    this.stopSession()
    const result = this.db.prepare('INSERT INTO sessions(started_at, mode) VALUES (?, ?)').run(new Date().toISOString(), mode)
    this.sessionId = Number(result.lastInsertRowid)
    this.logEvent(`Session started in ${mode} mode`)
    return this.sessionId
  }

  stopSession(): void {
    if (!this.sessionId) return
    this.logEvent('Session stopped')
    this.db.prepare('UPDATE sessions SET ended_at = ? WHERE id = ?').run(new Date().toISOString(), this.sessionId)
    this.sessionId = undefined
  }

  logExchange(command: string, source: string, raw?: string, error?: unknown): void {
    if (!this.sessionId) return
    const timestamp = new Date().toISOString()
    const result = this.db.prepare('INSERT INTO commands(session_id, timestamp, command, source, error) VALUES (?, ?, ?, ?, ?)')
      .run(this.sessionId, timestamp, command, source, error instanceof Error ? error.message : null)
    const commandId = Number(result.lastInsertRowid)
    if (raw) this.db.prepare('INSERT INTO responses(command_id, timestamp, raw_text) VALUES (?, ?, ?)').run(commandId, timestamp, raw)
  }

  logReading(reading: ObdReading): void {
    if (!this.sessionId) return
    this.db.prepare('INSERT INTO parsed_values(session_id, timestamp, pid, title, unit, value, raw_text) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(this.sessionId, reading.timestamp, reading.pid, reading.title, reading.unit, reading.value, reading.rawResponse)
  }

  logEvent(message: string): void {
    if (!this.sessionId) return
    this.db.prepare('INSERT INTO events(session_id, timestamp, message) VALUES (?, ?, ?)').run(this.sessionId, new Date().toISOString(), message)
  }

  listSessions(): SessionSummary[] {
    return this.db.prepare(`
      SELECT sessions.id, started_at AS startedAt, ended_at AS endedAt, mode,
        COUNT(commands.id) AS commandCount
      FROM sessions LEFT JOIN commands ON commands.session_id = sessions.id
      GROUP BY sessions.id ORDER BY sessions.id DESC
    `).all() as SessionSummary[]
  }

  getLogs(sessionId = this.sessionId): LogEntry[] {
    if (!sessionId) return []
    return this.db.prepare(`
      SELECT commands.id, commands.timestamp, 'TX' AS direction, commands.command, commands.command AS payload
      FROM commands WHERE commands.session_id = ?
      UNION ALL
      SELECT responses.id, responses.timestamp, 'RX' AS direction, commands.command, responses.raw_text AS payload
      FROM responses JOIN commands ON commands.id = responses.command_id WHERE commands.session_id = ?
      UNION ALL
      SELECT events.id, events.timestamp, 'EVENT' AS direction, NULL AS command, events.message AS payload
      FROM events WHERE events.session_id = ?
      ORDER BY timestamp ASC, id ASC
    `).all(sessionId, sessionId, sessionId) as LogEntry[]
  }

  exportSession(sessionId: number, format: 'json' | 'csv' | 'txt'): string {
    const session = this.listSessions().find((item) => item.id === sessionId)
    if (!session) throw new Error(`Session ${sessionId} not found`)
    const logs = this.getLogs(sessionId)
    if (format === 'json') return JSON.stringify({ session, logs }, null, 2)
    if (format === 'txt') return logs.map((log) => `${log.timestamp} [${log.direction}] ${log.command ?? ''} ${log.payload}`).join('\n')
    const escape = (value: unknown): string => `"${String(value ?? '').replaceAll('"', '""')}"`
    return ['timestamp,direction,command,payload', ...logs.map((log) => [log.timestamp, log.direction, log.command, log.payload].map(escape).join(','))].join('\n')
  }

  close(): void {
    this.stopSession()
    this.db.close()
  }

  private migrate(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);
      INSERT INTO schema_version(version) SELECT 0 WHERE NOT EXISTS (SELECT 1 FROM schema_version);
    `)
    const version = this.db.prepare('SELECT version FROM schema_version').pluck().get() as number
    if (version < 1) {
      this.db.exec(`
        CREATE TABLE sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          started_at TEXT NOT NULL,
          ended_at TEXT,
          mode TEXT NOT NULL
        );
        CREATE TABLE commands (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL REFERENCES sessions(id),
          timestamp TEXT NOT NULL,
          command TEXT NOT NULL,
          source TEXT NOT NULL,
          error TEXT
        );
        CREATE TABLE responses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          command_id INTEGER NOT NULL REFERENCES commands(id),
          timestamp TEXT NOT NULL,
          raw_text TEXT NOT NULL
        );
        CREATE TABLE events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL REFERENCES sessions(id),
          timestamp TEXT NOT NULL,
          message TEXT NOT NULL
        );
        CREATE TABLE parsed_values (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL REFERENCES sessions(id),
          timestamp TEXT NOT NULL,
          pid TEXT NOT NULL,
          title TEXT NOT NULL,
          unit TEXT NOT NULL,
          value REAL NOT NULL,
          raw_text TEXT NOT NULL
        );
        UPDATE schema_version SET version = 1;
      `)
    }
  }
}
