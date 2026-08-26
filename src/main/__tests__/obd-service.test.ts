import { describe, expect, it } from 'vitest'
import type { ObdTransport } from '../../core/transport'
import { ObdService } from '../obd-service'

class FakeTransport implements ObdTransport {
  readonly commands: string[] = []
  connected = false
  disconnects = 0

  constructor(readonly kind: 'mock' | 'serial') {}

  async connect(): Promise<void> { this.connected = true }
  async disconnect(): Promise<void> { this.connected = false; this.disconnects += 1 }
  isConnected(): boolean { return this.connected }
  async send(command: string): Promise<string> {
    this.commands.push(command)
    return ['ATZ', 'ATI'].includes(command) ? 'ELM327 v1.5\r>' : 'OK\r>'
  }
}

class FakeSerialTransport extends FakeTransport {
  portPath?: string
  baudRate?: number

  constructor() { super('serial') }

  async connect(portPath?: string, baudRate?: number): Promise<void> {
    this.portPath = portPath
    this.baudRate = baudRate
    await super.connect()
  }
}

class FakeLogger {
  readonly modes: string[] = []
  startSession(mode: string): number { this.modes.push(mode); return this.modes.length }
  stopSession(): void {}
  logExchange(): void {}
  logReading(): void {}
  logEvent(): void {}
}

describe('ObdService transport switching', () => {
  it('switches mock to serial and back without bypassing initialization queue', async () => {
    const mockTransports: FakeTransport[] = []
    const serialTransport = new FakeSerialTransport()
    const logger = new FakeLogger()
    const service = new ObdService(logger, {
      createMockTransport: () => {
        const transport = new FakeTransport('mock')
        mockTransports.push(transport)
        return transport
      },
      createSerialTransport: () => serialTransport
    })

    await service.connectMock()
    await service.connectSerial('COM7', 38400)
    expect(mockTransports[1].disconnects).toBe(1)
    expect(serialTransport.portPath).toBe('COM7')
    expect(serialTransport.baudRate).toBe(38400)
    expect(serialTransport.commands).toEqual(['ATZ', 'ATI', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0'])
    expect(service.getState()).toMatchObject({ connected: true, mode: 'serial', portPath: 'COM7', baudRate: 38400 })

    await service.connectMock()
    expect(serialTransport.disconnects).toBe(1)
    expect(service.getState()).toMatchObject({ connected: true, mode: 'mock' })
    expect(logger.modes).toEqual(['mock', 'serial', 'mock'])
    await service.stop()
  })
})
