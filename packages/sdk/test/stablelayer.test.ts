import { describe, it, expect } from 'vitest'
import { Transaction } from '@mysten/sui/transactions'
import { STABLELAYER_CONFIG } from '../src/stablelayer/constants.js'
import { StableLayerClient } from '../src/stablelayer/client.js'

describe('StableLayerClient', () => {
  const config = STABLELAYER_CONFIG.testnet

  it('initializes with testnet config', () => {
    const client = new StableLayerClient(config)
    expect(client.stablecoinType).toBe(config.stablecoinType)
    expect(client.farmPackageId).toBe(config.farmPackageId)
    expect(client.farmRegistryId).toBe(config.farmRegistryId)
  })

  it('has correct testnet addresses', () => {
    expect(config.packageId).toMatch(/^0x[a-f0-9]+$/)
    expect(config.registryId).toMatch(/^0x[a-f0-9]+$/)
    expect(config.farmPackageId).toMatch(/^0x[a-f0-9]+$/)
    expect(config.stablecoinType).toContain('stable_layer::Stablecoin')
    expect(config.usdbType).toContain('usdb::USDB')
  })

  describe('buildMintTx', () => {
    it('creates mint + farm::receive commands (hot-potato pattern)', () => {
      const client = new StableLayerClient(config)
      const tx = new Transaction()
      const mockCoin = tx.splitCoins(tx.gas, [100n])

      const stablecoin = client.buildMintTx({ tx, usdcCoin: mockCoin })
      // splitCoins + mint + receive = 3 commands
      expect(tx.getData().commands.length).toBe(3)
      expect(stablecoin).toBeDefined()
    })
  })

  describe('buildClaimTx', () => {
    it('creates farm::claim command returning USDB', () => {
      const client = new StableLayerClient(config)
      const tx = new Transaction()

      const result = client.buildClaimTx({ tx })
      expect(result).toBeDefined()
      expect(tx.getData().commands.length).toBe(1)
    })
  })

  describe('buildRedeemTx', () => {
    it('creates request_burn + farm::pay + fulfill_burn commands', () => {
      const client = new StableLayerClient(config)
      const tx = new Transaction()
      const mockStablecoin = tx.splitCoins(tx.gas, [100n])

      const usdcCoin = client.buildRedeemTx({ tx, stablecoinCoin: mockStablecoin })
      // splitCoins + request_burn + farm::pay + fulfill_burn = 4 commands
      expect(tx.getData().commands.length).toBe(4)
      expect(usdcCoin).toBeDefined()
    })
  })
})
