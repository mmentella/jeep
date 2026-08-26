import { SerialPort } from 'serialport'
import { Elm327Error } from '../errors'
import type { ObdTransport } from '../transport'
import type { SerialPortInfo } from '../types'

interface PortLike {
  readonly isOpen: boolean
  open(callback: (error: Error | null) => void): void
  close(callback: (error: Error | null) => void): void
  write(data: string, callback: (error?: Error | null) => void): boolean
  drain(callback: (error: Error | null) => void): void
  flush?(callback: (error: Error | null) => void): void
  on(event: 'data', listener: (data: Buffer) => void): this
  on(event: 'close' | 'error', listener: (error?: Error) => void): this
  off(event: 'data', listener: (data: Buffer) => void): this
  off(event: 'close' | 'error', listener: (error?: Error) => void): this
}

interface SerialObdTransportOptions {
  responseTimeoutMs?: number
  listPorts?: () => Promise<SerialPortInfo[]>
  createPort?: (path: string, baudRate: number) => PortLike
  onUnexpectedDisconnect?: (error: Elm327Error) => void
}

interface PendingResponse {
  raw: string
  resolve: (raw: string) => void
  reject: (error: Elm327Error) => void
  timer: NodeJS.Timeout
  signal?: AbortSignal
  abortListener?: () => void
}

export class SerialObdTransport implements ObdTransport {
  readonly kind = 'serial'
  private readonly responseTimeoutMs: number
  private readonly portLister: () => Promise<SerialPortInfo[]>
  private readonly portFactory: (path: string, baudRate: number) => PortLike
  private readonly onUnexpectedDisconnect?: (error: Elm327Error) => void
  private port?: PortLike
  private pending?: PendingResponse
  private expectedClose = false
  private connected = false
  private _lastRawResponse = ''
  private _lastNormalizedResponse = ''

  constructor(options: SerialObdTransportOptions = {}) {
    this.responseTimeoutMs = options.responseTimeoutMs ?? 5000
    this.portLister = options.listPorts ?? SerialObdTransport.listPorts
    this.portFactory = options.createPort ?? ((path, baudRate) => new SerialPort({ path, baudRate, autoOpen: false }))
    this.onUnexpectedDisconnect = options.onUnexpectedDisconnect
  }

  static async listPorts(): Promise<SerialPortInfo[]> {
    return (await SerialPort.list()).map(({ path, manufacturer, serialNumber, vendorId, productId }) => ({
      path, manufacturer, serialNumber, vendorId, productId
    }))
  }

  listPorts(): Promise<SerialPortInfo[]> {
    return this.portLister()
  }

  async connect(portPath?: string, baudRate = 38400): Promise<void> {
    if (!portPath) throw new Elm327Error('PORT_NOT_FOUND', 'Seleziona una porta COM')
    if (this.isConnected()) return
    const ports = await this.listPorts()
    if (!ports.some((port) => port.path.toUpperCase() === portPath.toUpperCase())) {
      throw new Elm327Error('PORT_NOT_FOUND', `Porta seriale ${portPath} non disponibile`)
    }

    const port = this.portFactory(portPath, baudRate)
    this.port = port
    this.expectedClose = false
    port.on('data', this.handleData)
    port.on('close', this.handleClose)
    port.on('error', this.handleError)
    try {
      await new Promise<void>((resolve, reject) => port.open((error) => error ? reject(error) : resolve()))
      this.connected = true
    } catch (error) {
      this.cleanupPort()
      throw this.mapPortError(error, portPath)
    }
  }

  async disconnect(): Promise<void> {
    const port = this.port
    this.expectedClose = true
    this.connected = false
    this.rejectPending(new Elm327Error('DISCONNECTED', 'Porta seriale disconnessa', this.pending?.raw))
    if (!port) return
    if (port.isOpen) {
      await new Promise<void>((resolve, reject) => port.close((error) => error ? reject(error) : resolve()))
    }
    this.cleanupPort()
  }

  isConnected(): boolean {
    return this.connected && Boolean(this.port?.isOpen)
  }

  async send(rawCommand: string, signal?: AbortSignal): Promise<string> {
    const port = this.port
    if (!this.isConnected() || !port) throw new Elm327Error('NOT_CONNECTED', 'Scanner OBD seriale non connesso')
    if (this.pending) throw new Elm327Error('ADAPTER_ERROR', 'Invio seriale concorrente non consentito')
    if (signal?.aborted) throw new Elm327Error('TIMEOUT', `Timeout ${rawCommand}`)
    const command = rawCommand.endsWith('\r') ? rawCommand : `${rawCommand}\r`

    await this.flush(port)
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.rejectPending(new Elm327Error('TIMEOUT', `Timeout risposta seriale per ${rawCommand}`, this.pending?.raw))
      }, this.responseTimeoutMs)
      const pending: PendingResponse = { raw: '', resolve, reject, timer, signal }
      if (signal) {
        pending.abortListener = () => this.rejectPending(new Elm327Error('TIMEOUT', `Timeout ${rawCommand}`, pending.raw))
        signal.addEventListener('abort', pending.abortListener, { once: true })
      }
      this.pending = pending
      port.write(command, (writeError) => {
        if (writeError) {
          this.rejectPending(this.mapPortError(writeError))
          return
        }
        port.drain((drainError) => {
          if (drainError) this.rejectPending(this.mapPortError(drainError))
        })
      })
    })
  }

  get lastRawResponse(): string {
    return this._lastRawResponse
  }

  get lastNormalizedResponse(): string {
    return this._lastNormalizedResponse
  }

  private readonly handleData = (data: Buffer): void => {
    if (!this.pending) return
    this.pending.raw += data.toString('utf8')
    const promptIndex = this.pending.raw.indexOf('>')
    if (promptIndex < 0) return
    const raw = this.pending.raw.slice(0, promptIndex + 1)
    this._lastRawResponse = raw
    this._lastNormalizedResponse = this.normalizeLineEndings(raw)
    this.resolvePending(raw)
  }

  private readonly handleClose = (error?: Error): void => {
    const wasExpected = this.expectedClose
    this.connected = false
    const disconnectError = new Elm327Error('DISCONNECTED', error?.message ?? 'Porta seriale disconnessa inaspettatamente', this.pending?.raw)
    this.rejectPending(disconnectError)
    this.cleanupPort()
    if (!wasExpected) this.onUnexpectedDisconnect?.(disconnectError)
  }

  private readonly handleError = (error?: Error): void => {
    if (this.pending) this.rejectPending(this.mapPortError(error))
  }

  private resolvePending(raw: string): void {
    const pending = this.takePending()
    pending?.resolve(raw)
  }

  private rejectPending(error: Elm327Error): void {
    const pending = this.takePending()
    pending?.reject(error)
  }

  private takePending(): PendingResponse | undefined {
    const pending = this.pending
    if (!pending) return undefined
    clearTimeout(pending.timer)
    if (pending.signal && pending.abortListener) pending.signal.removeEventListener('abort', pending.abortListener)
    this.pending = undefined
    return pending
  }

  private cleanupPort(): void {
    if (!this.port) return
    this.port.off('data', this.handleData)
    this.port.off('close', this.handleClose)
    this.port.off('error', this.handleError)
    this.port = undefined
  }

  private flush(port: PortLike): Promise<void> {
    if (!port.flush) return Promise.resolve()
    return new Promise((resolve, reject) => port.flush?.((error) => error ? reject(this.mapPortError(error)) : resolve()))
  }

  private normalizeLineEndings(raw: string): string {
    return raw.replace(/\r\n|\n/g, '\r')
  }

  private mapPortError(error: unknown, portPath?: string): Elm327Error {
    if (error instanceof Elm327Error) return error
    const message = error instanceof Error ? error.message : String(error ?? 'Errore porta seriale')
    if (/cannot find|not found|no such file|file not found/i.test(message)) {
      return new Elm327Error('PORT_NOT_FOUND', portPath ? `Porta seriale ${portPath} non disponibile` : message)
    }
    if (/access denied|busy|resource temporarily unavailable|permission denied/i.test(message)) {
      return new Elm327Error('PORT_BUSY', portPath ? `Porta seriale ${portPath} occupata o non accessibile` : message)
    }
    return new Elm327Error('ADAPTER_ERROR', message)
  }
}
