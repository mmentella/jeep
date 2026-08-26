import { Elm327Error } from './errors'
import type { Elm327Command, Elm327Frame, Elm327Response } from './types'

const textResponses = [
  (line: string) => line === 'OK',
  (line: string) => line.startsWith('ELM327'),
  (line: string) => line.endsWith('V'),
  (line: string) => line.includes('ISO '),
  (line: string) => line.startsWith('AUTO,')
]

export class Elm327FrameParser {
  static normalize(rawText: string): string {
    return rawText.toUpperCase().replaceAll('>', '').trim()
  }

  static parse(rawText: string, command: Elm327Command): Elm327Response {
    const normalizedText = this.normalize(rawText)
    const lines = normalizedText.split(/[\r\n]+/)
      .map((line) => line.trim())
      .filter((line) => line && line !== '>' && line !== command.command)

    this.throwAdapterError(normalizedText, rawText)
    const frames: Elm327Frame[] = []
    let sawSearching = false

    for (const line of lines) {
      if (line === 'SEARCHING...') {
        sawSearching = true
        continue
      }
      if (textResponses.some((matches) => matches(line))) continue
      const frame = this.parseFrameLine(line, rawText)
      for (let index = 0; index < frame.bytes.length - 2; index += 1) {
        if (frame.bytes[index] === 0x7f) {
          throw new Elm327Error('NEGATIVE_RESPONSE', `ECU negative response service=${this.hex(frame.bytes[index + 1])} code=${this.hex(frame.bytes[index + 2])}`, rawText)
        }
      }
      frames.push(frame)
    }

    if (sawSearching && frames.length === 0 && !lines.includes('OK')) {
      throw new Elm327Error('SEARCHING', 'ELM327: SEARCHING without final response', rawText)
    }
    if (command.expectedResponsePrefix) {
      const haystack = normalizedText.replaceAll(' ', '')
      const needle = command.expectedResponsePrefix.replaceAll(' ', '').toUpperCase()
      if (!haystack.includes(needle)) throw new Elm327Error('UNEXPECTED_RESPONSE', `Expected response prefix ${needle}`, rawText)
    }
    if (frames.length === 0 && !lines.some((line) => textResponses.some((matches) => matches(line)))) {
      throw new Elm327Error('MALFORMED_FRAME', 'ELM327: malformed frame', rawText)
    }
    return { command, rawText, normalizedText, lines, frames, promptSeen: rawText.includes('>'), isOK: lines.includes('OK') }
  }

  private static throwAdapterError(normalized: string, raw: string): void {
    if (normalized.includes('UNABLE TO CONNECT')) throw new Elm327Error('UNABLE_TO_CONNECT', 'ELM327: UNABLE TO CONNECT', raw)
    if (normalized.includes('BUS ERROR') || normalized.includes('BUS INIT: ERROR')) throw new Elm327Error('BUS_ERROR', 'ELM327: BUS ERROR', raw)
    if (normalized.includes('CAN ERROR')) throw new Elm327Error('CAN_ERROR', 'ELM327: CAN ERROR', raw)
    if (normalized.includes('BUFFER FULL') || normalized.includes('RX ERROR')) throw new Elm327Error('ADAPTER_ERROR', 'ELM327: BUFFER/RX ERROR', raw)
    if (normalized.includes('STOPPED')) throw new Elm327Error('STOPPED', 'ELM327: STOPPED', raw)
    if (normalized.includes('NO DATA')) throw new Elm327Error('NO_DATA', 'ELM327: NO DATA', raw)
    if (normalized.includes('?')) throw new Elm327Error('ADAPTER_ERROR', 'ELM327: unrecognized command', raw)
  }

  private static parseFrameLine(line: string, raw: string): Elm327Frame {
    const tokens = line.split(/\s+/)
    let header: string | undefined
    const bytes: number[] = []
    for (const token of tokens) {
      if (!header && /^[0-9A-F]{3}$/.test(token)) {
        header = token
      } else if (/^[0-9A-F]{2}$/.test(token)) {
        bytes.push(Number.parseInt(token, 16))
      } else if (/^(?:[0-9A-F]{2})+$/.test(token)) {
        for (let index = 0; index < token.length; index += 2) bytes.push(Number.parseInt(token.slice(index, index + 2), 16))
      } else {
        throw new Elm327Error('MALFORMED_FRAME', 'ELM327: malformed frame', raw)
      }
    }
    if (!bytes.length) throw new Elm327Error('MALFORMED_FRAME', 'ELM327: malformed frame', raw)
    return { header, bytes, line }
  }

  private static hex(byte: number): string {
    return byte.toString(16).padStart(2, '0').toUpperCase()
  }
}
