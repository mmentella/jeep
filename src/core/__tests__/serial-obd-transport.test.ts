import { EventEmitter } from 'node:events'
import { describe, expect, it } from 'vitest'
import { Elm327CommandQueue } from '../elm327-command-queue'
import { SerialObdTransport } from '../transports/serial-obd-transport'

class FakePort extends EventEmitter {
  isOpen = false
  readonly writes: string[] = []

  open(callback: (error: Error | null) => void): void {
    this.isOpen = true
    callback(null)
  }

  close(callback: (error: Error | null) => void): void {
    this.isOpen = false
    callback(null)
    this.emit('close')
  }

  write(data: string, callback: (error?: Error | null) => void): boolean {
    this.writes.push(data)
    callback(null)
    return true
  }

  drain(callback: (error: Error | null) => void): void {
    callback(null)
  }

  flush(callback: (error: Error | null) => void): void {
    callback(null)
  }

  receive(data: string): void {
    this.emit('data', Buffer.from(data))
  }

  unplug(): void {
    this.isOpen = false
    this.emit('close', new Error('USB adapter removed'))
  }
}

function setup(responseTimeoutMs = 100): { port: FakePort; transport: SerialObdTransport } {
  const port = new FakePort()
  const transport = new SerialObdTransport({
    responseTimeoutMs,
    listPorts: async () => [{ path: 'COM7', manufacturer: 'Vgate' }],
    createPort: () => port
  })
  return { port, transport }
}

async function waitForWrite(port: FakePort): Promise<void> {
  for (let attempt = 0; attempt < 5 && port.writes.length === 0; attempt += 1) {
    await new Promise<void>((resolve) => setImmediate(resolve))
  }
}

describe('SerialObdTransport', () => {
  it('adds carriage return framing and waits for the ELM327 prompt', async () => {
    const { port, transport } = setup()
    await transport.connect('COM7', 38400)
    const response = transport.send('010C')
    await waitForWrite(port)
    expect(port.writes).toEqual(['010C\r'])
    port.receive('41 0C 0F')
    let settled = false
    void response.then(() => { settled = true })
    await Promise.resolve()
    expect(settled).toBe(false)
    port.receive(' A0\r>')
    await expect(response).resolves.toBe('41 0C 0F A0\r>')
  })

  it('preserves multiline raw text and exposes transport-level CR/LF normalization', async () => {
    const { port, transport } = setup()
    await transport.connect('COM7', 115200)
    const response = transport.send('0100\r')
    await waitForWrite(port)
    port.receive('SEARCHING...\r\n41 00 BE 3E B8 13\n>')
    await expect(response).resolves.toBe('SEARCHING...\r\n41 00 BE 3E B8 13\n>')
    expect(port.writes).toEqual(['0100\r'])
    expect(transport.lastRawResponse).toBe('SEARCHING...\r\n41 00 BE 3E B8 13\n>')
    expect(transport.lastNormalizedResponse).toBe('SEARCHING...\r41 00 BE 3E B8 13\r>')
  })

  it('allows the queue parser to ignore an echoed command', async () => {
    const { port, transport } = setup()
    await transport.connect('COM7')
    const response = new Elm327CommandQueue(transport).execute({ command: '010C', source: 'manual', expectedResponsePrefix: '410C' })
    await waitForWrite(port)
    port.receive('010C\r41 0C 0F A0\r>')
    await expect(response).resolves.toMatchObject({ frames: [{ bytes: [0x41, 0x0c, 0x0f, 0xa0] }] })
  })

  it('times out with a partial response when the prompt never arrives', async () => {
    const { port, transport } = setup(10)
    await transport.connect('COM7')
    const response = transport.send('ATI')
    await waitForWrite(port)
    port.receive('ELM327 v1.5\r')
    await expect(response).rejects.toMatchObject({ code: 'TIMEOUT', raw: 'ELM327 v1.5\r' })
  })

  it('rejects an in-flight command when the adapter disconnects', async () => {
    const { port, transport } = setup()
    await transport.connect('COM7')
    const response = transport.send('010C')
    await waitForWrite(port)
    port.receive('41 0C')
    port.unplug()
    await expect(response).rejects.toMatchObject({ code: 'DISCONNECTED', raw: '41 0C' })
    expect(transport.isConnected()).toBe(false)
  })

  it('fails before opening when the selected port is unavailable', async () => {
    const transport = new SerialObdTransport({ listPorts: async () => [{ path: 'COM3' }] })
    await expect(transport.connect('COM7')).rejects.toMatchObject({ code: 'PORT_NOT_FOUND' })
  })
})
