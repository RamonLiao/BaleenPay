import { describe, it, expect } from 'vitest'
import { Transaction } from '@mysten/sui/transactions'
import { STABLELAYER_CONFIG } from '../src/stablelayer/constants.js'
import { StableLayerClient } from '../src/stablelayer/client.js'

describe('StableLayerClient', () => {
  const config = STABLELAYER_CONFIG.testnet

  it('initializes with testnet config', () => {
    const client = new StableLayerClient(config)
    expect(client.busdCoinType).toBe(config.busdCoinType)
  })

  it('has correct testnet addresses', () => {
    expect(config.packageId).toMatch(/^0x[a-f0-9]+$/)
    expect(config.registryId).toMatch(/^0x[a-f0-9]+$/)
    expect(config.busdCoinType).toContain('stable_layer::Stablecoin')
  })

  describe('buildMintTx', () => {
    it('creates a transaction with StableLayer mint call', () => {
      const client = new StableLayerClient(config)
      const tx = new Transaction()
      const mockCoin = tx.splitCoins(tx.gas, [100n])

      client.buildMintTx({ tx, usdcCoin: mockCoin })
      expect(tx.getData().commands.length).toBeGreaterThan(1)
    })
  })

  describe('buildClaimTx', () => {
    it('creates a transaction with StableLayer claim call', () => {
      const client = new StableLayerClient(config)
      const tx = new Transaction()

      const result = client.buildClaimTx({ tx })
      expect(result).toBeDefined()
    })
  })
})
