import { describe, expect, it } from 'vitest'
import { Elm327Error } from '../errors'
import { Elm327FrameParser } from '../elm327-frame-parser'

describe('Elm327FrameParser', () => {
  it('parses OK and searching responses', () => {
    expect(Elm327FrameParser.parse('OK\r>', { command: 'ATE0', source: 'initialization', expectedResponsePrefix: 'OK' }).isOK).toBe(true)
    expect(Elm327FrameParser.parse('SEARCHING...\r41 0C 0F A0\r>', { command: '010C', source: 'polling', expectedResponsePrefix: '410C' }).frames[0].bytes).toEqual([0x41, 0x0c, 0x0f, 0xa0])
  })

  it('parses CAN headers and compact frames', () => {
    const response = Elm327FrameParser.parse('7E8 03 41 05 5A\r>', { command: '0105', source: 'polling', expectedResponsePrefix: '4105' })
    expect(response.frames[0]).toMatchObject({ header: '7E8', bytes: [0x03, 0x41, 0x05, 0x5a] })
  })

  it.each([['NO DATA', 'NO_DATA'], ['STOPPED', 'STOPPED'], ['BUS ERROR', 'BUS_ERROR'], ['CAN ERROR', 'CAN_ERROR'], ['UNABLE TO CONNECT', 'UNABLE_TO_CONNECT']])('throws typed error for %s', (raw, code) => {
    expect(() => Elm327FrameParser.parse(`${raw}\r>`, { command: '010C', source: 'polling' })).toThrowError(expect.objectContaining({ code }))
  })

  it('rejects malformed and negative responses', () => {
    expect(() => Elm327FrameParser.parse('7E8 Z1\r>', { command: '010C', source: 'polling' })).toThrow(Elm327Error)
    expect(() => Elm327FrameParser.parse('7E8 03 7F 22 31\r>', { command: '22F190', source: 'manual' })).toThrowError(expect.objectContaining({ code: 'NEGATIVE_RESPONSE' }))
  })
})
