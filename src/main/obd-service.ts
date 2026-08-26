import { EventEmitter } from 'node:events'
import { Elm327CommandQueue } from '../core/elm327-command-queue'
import { ObdCommandPolicy } from '../core/obd-command-policy'
import { OBD_PIDS, OBD_PID_BY_COMMAND } from '../core/obd-pids'
import { ObdValueParser } from '../core/obd-value-parser'
import type { ObdTransport } from '../core/transport'
import { MockObdTransport } from '../core/transports/mock-obd-transport'
import { SerialObdTransport } from '../core/transports/serial-obd-transport'
import type { ObdConnectionState, ObdReading, SerialPortInfo } from '../core/types'

interface ObdLogger {
  startSession(mode: string): number
  stopSession(): void
  logExchange(command: string, source: string, raw?: string, error?: unknown): void
  logReading(reading: ObdReading): void
  logEvent(message: string): void
}

interface SerialTransport extends ObdTransport {
  connect(portPath?: string, baudRate?: number): Promise<void>
}

interface ObdServiceOptions {
  createMockTransport?: () => ObdTransport
  createSerialTransport?: (onUnexpectedDisconnect: (error: Error) => void) => SerialTransport
  listSerialPorts?: () => Promise<SerialPortInfo[]>
}

export class ObdService extends EventEmitter {
  private transport: ObdTransport
  private queue: Elm327CommandQueue
  private polling?: NodeJS.Timeout
  private pollInFlight = false
  private pollIndex = 0
  private state: ObdConnectionState = { connected: false, mode: 'mock' }

  constructor(private readonly logger: ObdLogger, private readonly options: ObdServiceOptions = {}) {
    super()
    this.transport = this.createMockTransport()
    this.queue = this.createQueue(this.transport)
  }

  start(): Promise<void> {
    return this.connectMock()
  }

  async connectMock(): Promise<void> {
    if (this.state.connected && this.transport.kind === 'mock') return
    await this.stop()
    const transport = this.createMockTransport()
    await this.activate(transport)
  }

  async connectSerial(portPath: string, baudRate: number): Promise<void> {
    if (this.state.connected && this.transport.kind === 'serial' && this.state.portPath === portPath && this.state.baudRate === baudRate) return
    await this.stop()
    const transport = this.options.createSerialTransport?.((error) => this.handleUnexpectedDisconnect(error.message))
      ?? new SerialObdTransport({ onUnexpectedDisconnect: (error) => this.handleUnexpectedDisconnect(error.message) })
    try {
      await transport.connect(portPath, baudRate)
      await this.activate(transport, portPath, baudRate)
    } catch (error) {
      await transport.disconnect().catch(() => undefined)
      this.updateState({ connected: false, mode: 'serial', portPath, baudRate, lastError: this.errorMessage(error) })
      throw error
    }
  }

  listSerialPorts(): Promise<SerialPortInfo[]> {
    return this.options.listSerialPorts?.() ?? SerialObdTransport.listPorts()
  }

  getState(): ObdConnectionState {
    return this.state
  }

  async stop(): Promise<void> {
    this.stopPolling()
    await this.transport.disconnect()
    this.logger.stopSession()
    this.updateState({ ...this.state, connected: false })
  }

  async sendManual(rawCommand: string, confirmWarning = false): Promise<{ rawText: string; warning?: string }> {
    const command = ObdCommandPolicy.normalize(rawCommand)
    const decision = ObdCommandPolicy.evaluate(command)
    if (decision.kind === 'block') throw new Error(decision.reason)
    if (decision.kind === 'warn' && !confirmWarning) return { rawText: '', warning: decision.reason }
    const response = await this.queue.execute({ command, source: 'manual', timeoutMs: 5000 })
    return { rawText: response.rawText }
  }

  private async activate(transport: ObdTransport, portPath?: string, baudRate?: number): Promise<void> {
    if (!transport.isConnected()) await transport.connect()
    this.transport = transport
    this.queue = this.createQueue(transport)
    this.logger.startSession(transport.kind)
    try {
      for (const command of ['ATZ', 'ATI', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0']) {
        await this.queue.execute({ command, source: 'initialization', expectedResponsePrefix: command.startsWith('AT') && !['ATZ', 'ATI'].includes(command) ? 'OK' : undefined })
      }
    } catch (error) {
      this.logger.logEvent(`Inizializzazione ${transport.kind} fallita: ${this.errorMessage(error)}`)
      this.logger.stopSession()
      await transport.disconnect().catch(() => undefined)
      throw error
    }
    this.logger.logEvent(`${transport.kind === 'mock' ? 'Mock' : 'Serial'} ELM327 initialized`)
    this.polling = setInterval(() => void this.pollNext(), 350)
    this.updateState({ connected: true, mode: transport.kind as 'mock' | 'serial', portPath, baudRate })
  }

  private createQueue(transport: ObdTransport): Elm327CommandQueue {
    return new Elm327CommandQueue(transport, (command, raw, error) => {
      this.logger.logExchange(command.command, command.source, raw, error)
      this.emit('logs')
    })
  }

  private createMockTransport(): ObdTransport {
    return this.options.createMockTransport?.() ?? new MockObdTransport()
  }

  private async pollNext(): Promise<void> {
    if (!this.transport.isConnected() || this.pollInFlight) return
    this.pollInFlight = true
    const pid = OBD_PIDS[this.pollIndex++ % OBD_PIDS.length]
    try {
      const response = await this.queue.execute({ command: pid.command, source: 'polling', expectedResponsePrefix: `41${pid.command.slice(2)}` })
      const reading: ObdReading = {
        pid: pid.command,
        title: pid.title,
        unit: pid.unit,
        value: ObdValueParser.parse(response.normalizedText, OBD_PID_BY_COMMAND.get(pid.command)!),
        rawResponse: response.rawText,
        timestamp: new Date().toISOString()
      }
      this.logger.logReading(reading)
      this.emit('reading', reading)
    } catch (error) {
      this.logger.logEvent(this.errorMessage(error))
    } finally {
      this.pollInFlight = false
    }
  }

  private stopPolling(): void {
    if (this.polling) clearInterval(this.polling)
    this.polling = undefined
  }

  private handleUnexpectedDisconnect(message: string): void {
    this.stopPolling()
    this.logger.logEvent(message)
    this.logger.stopSession()
    this.updateState({ ...this.state, connected: false, lastError: message })
  }

  private updateState(state: ObdConnectionState): void {
    this.state = state
    this.emit('state', state)
  }

  private errorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error)
  }
}
