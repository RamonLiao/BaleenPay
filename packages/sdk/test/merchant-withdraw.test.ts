import { describe, it, expect } from 'vitest'
import { buildMerchantWithdraw } from '../src/transactions/merchant.js'
import type { BaleenPayConfig } from '../src/types.js'

const testConfig: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0x5eea0defa80c75a3f20588e01dba2f57a1e97ad154a487ab0c1979c34c8855e8',
  merchantId: '0x9ec4bd37033ccfa03da3a74a1c0d251b840610d602417ed17cc7f98cc9be221b',
  vaultId: '0x6c7f42f261ba273c360d88c7518b8d70968ff915d25e62466c60923543203dad',
}

describe('buildMerchantWithdraw', () => {
  it('creates merchant_withdraw moveCall', () => {
    const tx = buildMerchantWithdraw(testConfig, {
      merchantCapId: '0x7ba95f5f4932423df5c6fb6a6d65d3298aa2f874eb5741348ba4bb35b9bdb83f',
      amount: 500000n,
      coinType: 'USDC',
    })
    const commands = tx.getData().commands
    expect(commands.length).toBe(1)
  })

  it('throws on zero amount', () => {
    expect(() =>
      buildMerchantWithdraw(testConfig, {
        merchantCapId: '0xabc',
        amount: 0n,
        coinType: 'USDC',
      }),
    ).toThrow('Amount must be greater than zero')
  })

  it('throws without vaultId', () => {
    const noVaultConfig = { ...testConfig, vaultId: undefined }
    expect(() =>
      buildMerchantWithdraw(noVaultConfig, {
        merchantCapId: '0xabc',
        amount: 100n,
        coinType: 'USDC',
      }),
    ).toThrow('vaultId is required')
  })
})
