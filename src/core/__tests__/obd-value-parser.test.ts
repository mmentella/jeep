import { describe, expect, it } from 'vitest'
import { OBD_PID_BY_COMMAND } from '../obd-pids'
import { ObdValueParser } from '../obd-value-parser'

const parse = (raw: string, pid: string): number => ObdValueParser.parse(raw, OBD_PID_BY_COMMAND.get(pid)!)

describe('ObdValueParser', () => {
  it('parses standard PIDs', () => {
    expect(parse('41 0C 1A F8', '010C')).toBe(1726)
    expect(parse('41 0D 3E', '010D')).toBe(62)
    expect(parse('41 05 5F', '0105')).toBe(55)
    expect(parse('41 42 31 10', '0142')).toBeCloseTo(12.56)
    expect(parse('41 04 80', '0104')).toBeCloseTo(50.196)
    expect(parse('41 11 40', '0111')).toBeCloseTo(25.098)
  })

  it('handles noise, compact payloads and CAN headers', () => {
    expect(parse('SEARCHING...\r\n41 0C 0F A0\r\n>', '010C')).toBe(1000)
    expect(parse('410D2A>', '010D')).toBe(42)
    expect(parse('7E8 03 41 05 5A', '0105')).toBe(50)
  })
})
