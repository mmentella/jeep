export type PolicyDecision =
  | { kind: 'allow' }
  | { kind: 'warn'; reason: string }
  | { kind: 'block'; reason: string }

const allowedAt = new Set(['ATZ', 'ATI', 'ATRV', 'ATDP', 'ATDPN', 'AT@1', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0'])
const standardReads = new Set(['01', '02', '03', '07', '09', '0A'])
const readLike = new Set(['18', '19', '22'])
const blocked = new Set(['04', '10', '11', '14', '27', '28', '2E', '2F', '31', '34', '35', '36', '37', '3B', '85'])

export class ObdCommandPolicy {
  static normalize(raw: string): string {
    return raw.trim().toUpperCase().replace(/[\r\n ]/g, '')
  }

  static evaluate(raw: string): PolicyDecision {
    const command = this.normalize(raw)
    if (!command) return { kind: 'block', reason: 'Inserisci un comando OBD/ELM327.' }
    if (command.startsWith('AT')) return allowedAt.has(command) ? { kind: 'allow' } : { kind: 'block', reason: 'Comando AT non consentito nel PID Lab.' }
    if (!/^(?:[0-9A-F]{2})+$/.test(command)) return { kind: 'block', reason: 'Usa byte esadecimali completi, ad esempio 010C o 22F190.' }
    const service = command.slice(0, 2)
    if (blocked.has(service)) return { kind: 'block', reason: `Servizio ${service} bloccato: scritture, reset, security access e programmazione non sono consentiti.` }
    if (standardReads.has(service)) return { kind: 'allow' }
    if (readLike.has(service)) return { kind: 'warn', reason: `Servizio ${service} non standard: inviare solo letture verificate e a veicolo in condizioni sicure.` }
    return { kind: 'block', reason: `Servizio ${service} non permesso: sono ammessi solo comandi di lettura.` }
  }
}
