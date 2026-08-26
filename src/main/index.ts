import { app, BrowserWindow, dialog, ipcMain } from 'electron'
import { writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { ObdService } from './obd-service'
import { ObdSessionLogger } from './storage'

let window: BrowserWindow | undefined
let logger: ObdSessionLogger
let obd: ObdService

function createWindow(): void {
  window = new BrowserWindow({
    width: 1440,
    height: 940,
    minWidth: 1040,
    minHeight: 700,
    backgroundColor: '#0b0f14',
    title: 'Jeep Notebook',
    webPreferences: {
      preload: join(__dirname, '../preload/index.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })
  window.webContents.on('did-finish-load', () => {
    void window?.webContents.executeJavaScript('Boolean(window.jeepNotebook)').then((available) => {
      console.log(`Preload bridge available: ${available}`)
    })
  })
  if (process.env.ELECTRON_RENDERER_URL) window.loadURL(process.env.ELECTRON_RENDERER_URL)
  else window.loadFile(join(__dirname, '../renderer/index.html'))
}

function registerIpc(): void {
  ipcMain.handle('obd:start', () => obd.start())
  ipcMain.handle('obd:stop', () => obd.stop())
  ipcMain.handle('obd:state:get', () => obd.getState())
  ipcMain.handle('obd:serial:list', () => obd.listSerialPorts())
  ipcMain.handle('obd:serial:connect', (_, portPath: string, baudRate: number) => obd.connectSerial(portPath, baudRate))
  ipcMain.handle('obd:mock:connect', () => obd.connectMock())
  ipcMain.handle('obd:manual', (_, command: string, confirmWarning: boolean) => obd.sendManual(command, confirmWarning))
  ipcMain.handle('sessions:list', () => logger.listSessions())
  ipcMain.handle('sessions:logs', (_, sessionId?: number) => logger.getLogs(sessionId))
  ipcMain.handle('sessions:export', async (_, sessionId: number, format: 'json' | 'csv' | 'txt') => {
    const result = await dialog.showSaveDialog({ defaultPath: `jeep-notebook-session-${sessionId}.${format}` })
    if (result.canceled || !result.filePath) return false
    await writeFile(result.filePath, logger.exportSession(sessionId, format), 'utf8')
    return true
  })
  obd.on('reading', (reading) => window?.webContents.send('obd:reading', reading))
  obd.on('state', (state) => window?.webContents.send('obd:state', state))
  obd.on('logs', () => window?.webContents.send('obd:logs'))
}

app.whenReady().then(() => {
  logger = new ObdSessionLogger(join(app.getPath('userData'), 'jeep-notebook.db'))
  obd = new ObdService(logger)
  registerIpc()
  createWindow()
  void obd.start().catch((error) => console.error('Failed to start mock OBD service', error))
})

app.on('window-all-closed', () => app.quit())
app.on('before-quit', () => {
  logger?.close()
})
