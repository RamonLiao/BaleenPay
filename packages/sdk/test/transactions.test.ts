import { describe, it, expect } from 'vitest'
import { buildRegisterMerchant, buildSelfPause, buildClaimYield } from '../src/transactions/index.js'
import type { FloatSyncConfig } from '../src/types.js'

const config: FloatSyncConfig = {
  network: 'testnet',
  packageId: '0x1234',
  merchantId: '0xabcd',
  registryId: '0x5678',
  routerConfigId: '0x9999',
}

describe('buildRegisterMerchant', () => {
  it('creates a valid transaction', () => {
    const tx = buildRegisterMerchant(config, { brandName: 'TestShop' })
    expect(tx).toBeDefined()
    expect(tx.getData).toBeDefined()
  })

  it('throws without registryId', () => {
    const noRegistry = { ...config, registryId: undefined }
    expect(() => buildRegisterMerchant(noRegistry, { brandName: 'Test' })).toThrow('registryId')
  })
})

describe('buildSelfPause', () => {
  it('creates a valid transaction', () => {
    const tx = buildSelfPause(config, '0xcap')
    expect(tx).toBeDefined()
  })
})

describe('buildClaimYield', () => {
  it('creates a valid transaction', () => {
    const tx = buildClaimYield(config, '0xcap')
    expect(tx).toBeDefined()
  })

  it('throws without routerConfigId', () => {
    const noRouter = { ...config, routerConfigId: undefined }
    expect(() => buildClaimYield(noRouter, '0xcap')).toThrow('routerConfigId')
  })
})
