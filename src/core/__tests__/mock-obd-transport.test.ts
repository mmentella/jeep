import { describe, expect, it } from 'vitest'
import { MockObdTransport } from '../transports/mock-obd-transport'

describe('MockObdTransport', () => {
  it('simulates init, supported PID bitmap and variable values', async () => {
    const transport = new MockObdTransport()
    await transport.connect()
    await expect(transport.send('ATZ')).resolves.toContain('ELM327')
    await expect(transport.send('ATE0')).resolves.toContain('OK')
    await expect(transport.send('0100')).resolves.toContain('41 00')
    await expect(transport.send('010C')).resolves.toMatch(/41 0C [0-9A-F]{2} [0-9A-F]{2}/)
  })

  it('requires a connection', async () => {
    const transport = new MockObdTransport()
    await expect(transport.send('010C')).rejects.toMatchObject({ code: 'NOT_CONNECTED' })
  })
})
