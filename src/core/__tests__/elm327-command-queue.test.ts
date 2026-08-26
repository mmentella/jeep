import { describe, expect, it } from 'vitest'
import { Elm327CommandQueue } from '../elm327-command-queue'
import type { ObdTransport } from '../transport'

class ControlledTransport implements ObdTransport {
  readonly kind = 'mock'
  connected = true
  active = 0
  maxActive = 0
  commands: string[] = []
  async connect(): Promise<void> { this.connected = true }
  async disconnect(): Promise<void> { this.connected = false }
  isConnected(): boolean { return this.connected }
  async send(command: string, signal?: AbortSignal): Promise<string> {
    this.active += 1
    this.maxActive = Math.max(this.maxActive, this.active)
    this.commands.push(command)
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.active -= 1
        resolve(command === '010C' ? '41 0C 0F A0\r>' : '41 0D 2A\r>')
      }, command === 'SLOW' ? 300 : 20)
      signal?.addEventListener('abort', () => {
        clearTimeout(timer)
        this.active -= 1
        reject(new Error('aborted'))
      }, { once: true })
    })
  }
}

describe('Elm327CommandQueue', () => {
  it('serializes concurrent requests', async () => {
    const transport = new ControlledTransport()
    const queue = new Elm327CommandQueue(transport)
    await Promise.all([
      queue.execute({ command: '010C', source: 'polling' }),
      queue.execute({ command: '010D', source: 'manual' })
    ])
    expect(transport.commands).toEqual(['010C', '010D'])
    expect(transport.maxActive).toBe(1)
  })

  it('times out and releases the queue', async () => {
    const transport = new ControlledTransport()
    const queue = new Elm327CommandQueue(transport)
    await expect(queue.execute({ command: 'SLOW', source: 'manual', timeoutMs: 20 })).rejects.toMatchObject({ code: 'TIMEOUT' })
    await expect(queue.execute({ command: '010D', source: 'manual' })).resolves.toBeTruthy()
  })
})
