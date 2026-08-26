import { describe, expect, it } from 'vitest'
import { ObdCommandPolicy } from '../obd-command-policy'

describe('ObdCommandPolicy', () => {
  it('allows read commands and AT allowlist', () => {
    expect(ObdCommandPolicy.evaluate('010C').kind).toBe('allow')
    expect(ObdCommandPolicy.evaluate('0902').kind).toBe('allow')
    expect(ObdCommandPolicy.evaluate('ATRV').kind).toBe('allow')
  })

  it('warns on proprietary reads', () => expect(ObdCommandPolicy.evaluate('22F190').kind).toBe('warn'))
  it.each(['2EF1901234', '2701', '1101', '3101', '3400', '3500'])('blocks dangerous service %s', (command) => expect(ObdCommandPolicy.evaluate(command).kind).toBe('block'))
})
