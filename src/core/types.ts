export type CommandSource = 'initialization' | 'polling' | 'manual'

export interface Elm327Command {
  command: string
  timeoutMs?: number
  expectedResponsePrefix?: string
  source: CommandSource
}

export interface Elm327Frame {
  header?: string
  bytes: number[]
  line: string
}

export interface Elm327Response {
  command: Elm327Command
  rawText: string
  normalizedText: string
  lines: string[]
  frames: Elm327Frame[]
  promptSeen: boolean
  isOK: boolean
}

export interface ObdReading {
  pid: string
  title: string
  unit: string
  value: number
  rawResponse: string
  timestamp: string
}

export interface SessionSummary {
  id: number
  startedAt: string
  endedAt: string | null
  mode: string
  commandCount: number
}

export interface LogEntry {
  id: number
  timestamp: string
  direction: 'TX' | 'RX' | 'EVENT'
  command?: string
  payload: string
}

export interface SerialPortInfo {
  path: string
  manufacturer?: string
  serialNumber?: string
  vendorId?: string
  productId?: string
}

export interface ObdConnectionState {
  connected: boolean
  mode: 'mock' | 'serial'
  portPath?: string
  baudRate?: number
  lastError?: string
}
