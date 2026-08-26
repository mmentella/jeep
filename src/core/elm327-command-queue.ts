import { Elm327Error } from './errors'
import { Elm327FrameParser } from './elm327-frame-parser'
import type { ObdTransport } from './transport'
import type { Elm327Command, Elm327Response } from './types'

export class Elm327CommandQueue {
  private tail = Promise.resolve()

  constructor(
    private readonly transport: ObdTransport,
    private readonly onExchange?: (command: Elm327Command, raw?: string, error?: unknown) => void
  ) {}

  execute(command: Elm327Command): Promise<Elm327Response> {
    const task = this.tail.then(() => this.executeNow(command))
    this.tail = task.then(() => undefined, () => undefined)
    return task
  }

  private async executeNow(command: Elm327Command): Promise<Elm327Response> {
    const controller = new AbortController()
    const timeoutMs = Math.max(command.timeoutMs ?? 3000, 100)
    const timer = setTimeout(() => controller.abort(), timeoutMs)
    try {
      const raw = await this.transport.send(command.command, controller.signal)
      this.onExchange?.(command, raw)
      return Elm327FrameParser.parse(raw, command)
    } catch (error) {
      const finalError = controller.signal.aborted
        ? new Elm327Error('TIMEOUT', `Timeout ${command.command} after ${timeoutMs}ms`, error instanceof Elm327Error ? error.raw : undefined)
        : error
      this.onExchange?.(command, finalError instanceof Elm327Error ? finalError.raw : undefined, finalError)
      throw finalError
    } finally {
      clearTimeout(timer)
    }
  }
}
