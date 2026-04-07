import { describe, it, expect } from 'vitest'
import { buildMerchantRedeem } from '../src/transactions/redeem.js'
import type { BaleenPayConfig } from '../src/types.js'

const testConfig: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0x5eea0defa80c75a3f20588e01dba2f57a1e97ad154a487ab0c1979c34c8855e8',
  merchantId: '0x9ec4bd37033ccfa03da3a74a1c0d251b840610d602417ed17cc7f98cc9be221b',
  stablecoinVaultId: '0x1111111111111111111111111111111111111111111111111111111111111111',
}

describe('buildMerchantRedeem', () => {
  it('creates take_stablecoin + request_burn + farm::pay + fulfill_burn + transferObjects', () => {
    const tx = buildMerchantRedeem(testConfig, {
      merchantCapId: '0x7ba95f5f4932423df5c6fb6a6d65d3298aa2f874eb5741348ba4bb35b9bdb83f',
      amount: 1000000n,
      coinType: 'USDC',
      recipientAddress: '0xBB00000000000000000000000000000000000000000000000000000000000000',
    })
    const commands = tx.getData().commands
    // take_stablecoin + request_burn + farm::pay + fulfill_burn + transferObjects = 5
    expect(commands.length).toBe(5)
  })

  it('throws on zero amount', () => {
    expect(() =>
      buildMerchantRedeem(testConfig, {
        merchantCapId: '0xabc',
        amount: 0n,
        coinType: 'USDC',
        recipientAddress: '0xBB',
      }),
    ).toThrow('Amount must be greater than zero')
  })

  it('throws without stablecoinVaultId', () => {
    const noVaultConfig = { ...testConfig, stablecoinVaultId: undefined }
    expect(() =>
      buildMerchantRedeem(noVaultConfig, {
        merchantCapId: '0xabc',
        amount: 100n,
        coinType: 'USDC',
        recipientAddress: '0xBB',
      }),
    ).toThrow('stablecoinVaultId is required')
  })
})
