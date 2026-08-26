import { Elm327Error } from '../errors'
import type { ObdTransport } from '../transport'

export class MockObdTransport implements ObdTransport {
  readonly kind = 'mock'
  private connected = false
  private readonly startedAt = Date.now()
  private commandCount = 0

  async connect(): Promise<void> { this.connected = true }
  async disconnect(): Promise<void> { this.connected = false }
  isConnected(): boolean { return this.connected }

  async send(rawCommand: string, signal?: AbortSignal): Promise<string> {
    if (!this.connected) throw new Elm327Error('NOT_CONNECTED', 'Scanner OBD non connesso')
    const command = rawCommand.trim().toUpperCase()
    this.commandCount += 1
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(resolve, 20 + Math.random() * 35)
      signal?.addEventListener('abort', () => {
        clearTimeout(timer)
        reject(new Elm327Error('TIMEOUT', `Timeout ${command}`))
      }, { once: true })
    })
    return `${this.mockResponse(command)}\r>`
  }

  private mockResponse(command: string): string {
    switch (command) {
      case 'ATZ':
      case 'ATI': return 'ELM327 v1.5'
      case 'ATE0':
      case 'ATL0':
      case 'ATS0':
      case 'ATH0':
      case 'ATSP0': return 'OK'
      case 'ATRV': return `${this.voltage.toFixed(1)}V`
      case '0100': return '41 00 BE 3E B8 13'
      case '010C': return this.response(command, this.word(this.rpm * 4))
      case '010D': return this.response(command, [Math.round(this.speed)])
      case '0105': return this.response(command, [Math.round(this.coolant + 40)])
      case '0142': return this.response(command, this.word(this.voltage * 1000))
      case '0104': return this.response(command, [this.percentByte(this.load)])
      case '0111': return this.response(command, [this.percentByte(this.throttle)])
      default: return 'NO DATA'
    }
  }

  private get seconds(): number { return (Date.now() - this.startedAt) / 1000 }
  private get throttle(): number { return this.clamp(22 + Math.sin(this.seconds * 0.9) * 10 + Math.sin(this.seconds * 2.4) * 4 + this.commandCount % 5, 6, 72) }
  private get load(): number { return this.clamp(34 + Math.sin(this.seconds * 0.7) * 16 + this.throttle * 0.28, 12, 88) }
  private get rpm(): number { return Math.round(this.clamp(780 + this.throttle * 42 + Math.sin(this.seconds * 1.35) * 220, 720, 5200)) }
  private get speed(): number { return this.clamp(58 + Math.sin(this.seconds * 0.18) * 34 + Math.sin(this.seconds * 0.62) * 9, 0, 140) }
  private get coolant(): number { return this.clamp(58 + Math.min(this.seconds / 180, 1) * 34 + Math.sin(this.seconds * 0.08) * 2, 45, 103) }
  private get voltage(): number { return this.clamp(13.9 + Math.sin(this.seconds * 0.5) * 0.18, 12.1, 14.7) }
  private clamp(value: number, min: number, max: number): number { return Math.min(Math.max(value, min), max) }
  private word(value: number): number[] { const rounded = Math.round(value); return [(rounded >> 8) & 0xff, rounded & 0xff] }
  private percentByte(value: number): number { return Math.round(value / 100 * 255) }
  private response(command: string, bytes: number[]): string { return `41 ${command.slice(-2)} ${bytes.map((byte) => byte.toString(16).padStart(2, '0').toUpperCase()).join(' ')}` }
}
