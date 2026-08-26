import { Elm327Error } from './errors'
import type { ObdPid } from './obd-pids'

export class ObdValueParser {
  static parse(rawResponse: string, pid: ObdPid): number {
    const normalized = rawResponse.toUpperCase()
      .replaceAll('SEARCHING...', ' ').replace(/[\r\n>]/g, ' ').trim()
    if (!normalized || normalized.includes('NO DATA')) throw new Elm327Error('NO_DATA', 'No data', rawResponse)
    if (normalized.includes('7F') || normalized.includes('STOPPED') || normalized.includes('?')) throw new Elm327Error('NEGATIVE_RESPONSE', 'Negative ECU response', rawResponse)
    const bytes = this.tokenize(normalized, rawResponse)
    const pidByte = Number.parseInt(pid.command.slice(2), 16)
    const offset = bytes.findIndex((byte, index) => byte === 0x41 && bytes[index + 1] === pidByte)
    if (offset < 0) throw new Elm327Error('UNEXPECTED_RESPONSE', `PID mismatch for ${pid.command}`, rawResponse)
    const payload = bytes.slice(offset + 2)
    const require = (count: number): void => {
      if (payload.length < count) throw new Elm327Error('MALFORMED_FRAME', `Expected ${count} payload bytes`, rawResponse)
    }
    switch (pid.command) {
      case '010C': require(2); return (payload[0] * 256 + payload[1]) / 4
      case '010D': require(1); return payload[0]
      case '0105': require(1); return payload[0] - 40
      case '0142': require(2); return (payload[0] * 256 + payload[1]) / 1000
      case '0104':
      case '0111': require(1); return payload[0] * 100 / 255
      default: throw new Elm327Error('UNEXPECTED_RESPONSE', `Unsupported PID ${pid.command}`, rawResponse)
    }
  }

  private static tokenize(normalized: string, raw: string): number[] {
    const bytes: number[] = []
    for (const token of normalized.split(/\s+/)) {
      if (/^[0-9A-F]{3}$/.test(token)) continue
      if (!/^(?:[0-9A-F]{2})+$/.test(token)) throw new Elm327Error('MALFORMED_FRAME', 'Malformed OBD response', raw)
      for (let index = 0; index < token.length; index += 2) bytes.push(Number.parseInt(token.slice(index, index + 2), 16))
    }
    return bytes
  }
}
