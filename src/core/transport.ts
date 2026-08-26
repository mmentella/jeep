export interface ObdTransport {
  readonly kind: 'mock' | 'serial' | 'ble'
  connect(): Promise<void>
  disconnect(): Promise<void>
  isConnected(): boolean
  send(command: string, signal?: AbortSignal): Promise<string>
}
