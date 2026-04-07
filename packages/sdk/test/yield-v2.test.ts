import { describe, it, expect, vi } from 'vitest'
import { Transaction } from '@mysten/sui/transactions'
import { buildPayOnceRouted } from '../src/transactions/pay.js'
import { buildClaimYield, buildClaimYieldPartial } from '../src/transactions/yield.js'
import type { BaleenPayConfig, PayParams } from '../src/types.js'

const config: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0xPACKAGE',
  merchantId: '0xMERCHANT',
  routerConfigId: '0xROUTER',
  vaultId: '0xVAULT',
  yieldVaultId: '0xYIELD_VAULT',
}

const mockClient = {
  listCoins: vi.fn().mockResolvedValue({
    objects: [{ objectId: '0xCOIN1', balance: '1000000' }],
  }),
} as any

describe('buildPayOnceRouted', () => {
  it('builds pay_once_routed PTB with vault', async () => {
    const params: PayParams = { amount: 100n, coin: 'USDC', orderId: 'order-001' }
    const tx = await buildPayOnceRouted(mockClient, config, params, '0xSENDER')
    expect(tx).toBeInstanceOf(Transaction)
    expect(tx.getData).toBeDefined()
  })

  it('throws without vaultId in config', async () => {
    const noVaultConfig = { ...config, vaultId: undefined }
    const params: PayParams = { amount: 100n, coin: 'USDC', orderId: 'order-001' }
    await expect(buildPayOnceRouted(mockClient, noVaultConfig, params, '0xSENDER'))
      .rejects.toThrow('vaultId is required')
  })

  it('throws without routerConfigId', async () => {
    const noRouterConfig = { ...config, routerConfigId: undefined }
    const params: PayParams = { amount: 100n, coin: 'USDC', orderId: 'order-001' }
    await expect(buildPayOnceRouted(mockClient, noRouterConfig as any, params, '0xSENDER'))
      .rejects.toThrow('routerConfigId is required')
  })
})

describe('buildClaimYield (revised)', () => {
  it('builds claim_yield_v2 PTB with YieldVault when coinType provided', () => {
    const tx = buildClaimYield(config, '0xMERCHANT_CAP', 'USDB')
    expect(tx).toBeInstanceOf(Transaction)
    expect(tx.getData).toBeDefined()
  })

  it('throws without yieldVaultId', () => {
    const noYvConfig = { ...config, yieldVaultId: undefined }
    expect(() => buildClaimYield(noYvConfig, '0xCAP', 'USDB'))
      .toThrow('yieldVaultId is required')
  })
})

describe('buildClaimYieldPartial', () => {
  it('builds claim_yield_partial PTB with amount', () => {
    const tx = buildClaimYieldPartial(config, '0xMERCHANT_CAP', 'USDB', 500n)
    expect(tx).toBeInstanceOf(Transaction)
    expect(tx.getData).toBeDefined()
  })

  it('throws without yieldVaultId', () => {
    const noYvConfig = { ...config, yieldVaultId: undefined }
    expect(() => buildClaimYieldPartial(noYvConfig, '0xCAP', 'USDB', 100n))
      .toThrow('yieldVaultId is required')
  })

  it('throws on zero amount', () => {
    expect(() => buildClaimYieldPartial(config, '0xCAP', 'USDB', 0n))
      .toThrow('amount must be > 0')
  })

  it('throws on negative amount', () => {
    expect(() => buildClaimYieldPartial(config, '0xCAP', 'USDB', -1n))
      .toThrow('amount must be > 0')
  })
})
