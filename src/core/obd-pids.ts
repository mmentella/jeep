export interface ObdPid {
  command: string
  title: string
  unit: string
  range: [number, number]
}

export const OBD_PIDS: ObdPid[] = [
  { command: '010C', title: 'RPM', unit: 'rpm', range: [0, 7000] },
  { command: '010D', title: 'Velocita', unit: 'km/h', range: [0, 220] },
  { command: '0105', title: 'Temp. liquido', unit: 'C', range: [-40, 140] },
  { command: '0142', title: 'Voltaggio ECU', unit: 'V', range: [0, 18] },
  { command: '0104', title: 'Carico motore', unit: '%', range: [0, 100] },
  { command: '0111', title: 'Acceleratore', unit: '%', range: [0, 100] }
]

export const OBD_PID_BY_COMMAND = new Map(OBD_PIDS.map((pid) => [pid.command, pid]))
