import { describe, it, expect } from 'vitest'
import { buildRegisterMerchant, buildSelfPause, buildClaimYield } from '../src/transactions/index.js'
import type { BaleenPayConfig } from '../src/types.js'

const config: BaleenPayConfig = {
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
  it('creates a valid transaction with yieldVaultId + coinType', () => {
    const withYv = { ...config, yieldVaultId: '0xYV' }
    const tx = buildClaimYield(withYv, '0xcap', 'USDC')
    expect(tx).toBeDefined()
  })

  it('throws without yieldVaultId', () => {
    expect(() => buildClaimYield(config, '0xcap', 'USDC')).toThrow('yieldVaultId')
  })
})
