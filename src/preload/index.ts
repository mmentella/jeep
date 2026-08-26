import { contextBridge, ipcRenderer } from 'electron'
import type { LogEntry, ObdConnectionState, ObdReading, SerialPortInfo, SessionSummary } from '../core/types'

export interface JeepNotebookApi {
  start(): Promise<void>
  stop(): Promise<void>
  getState(): Promise<ObdConnectionState>
  listSerialPorts(): Promise<SerialPortInfo[]>
  connectSerial(portPath: string, baudRate: number): Promise<void>
  connectMock(): Promise<void>
  sendManual(command: string, confirmWarning?: boolean): Promise<{ rawText: string; warning?: string }>
  listSessions(): Promise<SessionSummary[]>
  getLogs(sessionId?: number): Promise<LogEntry[]>
  exportSession(sessionId: number, format: 'json' | 'csv' | 'txt'): Promise<boolean>
  onReading(listener: (reading: ObdReading) => void): () => void
  onState(listener: (state: ObdConnectionState) => void): () => void
  onLogs(listener: () => void): () => void
}

const api: JeepNotebookApi = {
  start: () => ipcRenderer.invoke('obd:start'),
  stop: () => ipcRenderer.invoke('obd:stop'),
  getState: () => ipcRenderer.invoke('obd:state:get'),
  listSerialPorts: () => ipcRenderer.invoke('obd:serial:list'),
  connectSerial: (portPath, baudRate) => ipcRenderer.invoke('obd:serial:connect', portPath, baudRate),
  connectMock: () => ipcRenderer.invoke('obd:mock:connect'),
  sendManual: (command, confirmWarning = false) => ipcRenderer.invoke('obd:manual', command, confirmWarning),
  listSessions: () => ipcRenderer.invoke('sessions:list'),
  getLogs: (sessionId) => ipcRenderer.invoke('sessions:logs', sessionId),
  exportSession: (sessionId, format) => ipcRenderer.invoke('sessions:export', sessionId, format),
  onReading: (listener) => {
    const handler = (_event: Electron.IpcRendererEvent, reading: ObdReading): void => listener(reading)
    ipcRenderer.on('obd:reading', handler)
    return () => ipcRenderer.off('obd:reading', handler)
  },
  onState: (listener) => {
    const handler = (_event: Electron.IpcRendererEvent, state: ObdConnectionState): void => listener(state)
    ipcRenderer.on('obd:state', handler)
    return () => ipcRenderer.off('obd:state', handler)
  },
  onLogs: (listener) => {
    const handler = (): void => listener()
    ipcRenderer.on('obd:logs', handler)
    return () => ipcRenderer.off('obd:logs', handler)
  }
}

contextBridge.exposeInMainWorld('jeepNotebook', api)
