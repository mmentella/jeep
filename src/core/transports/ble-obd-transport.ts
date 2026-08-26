import { Elm327Error } from '../errors'
import type { ObdTransport } from '../transport'

export class BleObdTransport implements ObdTransport {
  readonly kind = 'ble'
  async connect(): Promise<void> { throw new Elm327Error('NOT_CONNECTED', 'BLE transport placeholder: bind a Windows BLE GATT implementation') }
  async disconnect(): Promise<void> {}
  isConnected(): boolean { return false }
  async send(): Promise<string> { throw new Elm327Error('NOT_CONNECTED', 'BLE transport not configured') }
}
