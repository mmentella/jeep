export type Elm327ErrorCode =
  | 'NO_DATA' | 'STOPPED' | 'SEARCHING' | 'BUS_ERROR' | 'CAN_ERROR'
  | 'UNABLE_TO_CONNECT' | 'NEGATIVE_RESPONSE' | 'MALFORMED_FRAME'
  | 'UNEXPECTED_RESPONSE' | 'TIMEOUT' | 'ADAPTER_ERROR' | 'NOT_CONNECTED'
  | 'PORT_NOT_FOUND' | 'PORT_BUSY' | 'DISCONNECTED'

export class Elm327Error extends Error {
  constructor(
    public readonly code: Elm327ErrorCode,
    message: string,
    public readonly raw?: string
  ) {
    super(message)
    this.name = 'Elm327Error'
  }
}
