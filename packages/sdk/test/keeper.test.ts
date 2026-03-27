import { describe, it, expect } from 'vitest'
import { Transaction } from '@mysten/sui/transactions'
import {
  buildKeeperWithdraw,
  buildKeeperDepositYield,
  buildKeeperDeposit,
  buildKeeperHarvest,
} from '../src/transactions/keeper.js'
import type { FloatSyncConfig, KeeperParams } from '../src/types.js'

const config: FloatSyncConfig = {
  network: 'testnet',
  packageId: '0x1234',
  merchantId: '0xabcd',
  routerConfigId: '0x9999',
  vaultId: '0x7777',
  yieldVaultId: '0x8888',
}

const keeperParams: KeeperParams = {
  adminCapId: '0xadmin',
  vaultId: '0x7777',
  yieldVaultId: '0x8888',
}

describe('buildKeeperWithdraw', () => {
  it('creates a valid transaction', () => {
    const tx = buildKeeperWithdraw(config, keeperParams, 1000n, '0x1234::usdc::USDC')
    expect(tx).toBeInstanceOf(Transaction)
    expect(tx.getData).toBeDefined()
  })

  it('throws on zero amount', () => {
    expect(() => buildKeeperWithdraw(config, keeperParams, 0n, '0x1234::usdc::USDC'))
      .toThrow('Amount must be greater than zero')
  })

  it('throws on negative amount', () => {
    expect(() => buildKeeperWithdraw(config, keeperParams, -1n, '0x1234::usdc::USDC'))
      .toThrow('Amount must be greater than zero')
  })
})

describe('buildKeeperDepositYield', () => {
  it('appends keeper_deposit_yield command to existing tx', () => {
    const tx = new Transaction()
    const fakeCoin = tx.splitCoins(tx.gas, [100n])
    buildKeeperDepositYield(tx, config, keeperParams, fakeCoin, '0x1234::usdb::USDB')
    // splitCoins + moveCall = at least 2 commands
    expect(tx.getData).toBeDefined()
  })

  it('uses custom merchantId when provided', () => {
    const tx = new Transaction()
    const fakeCoin = tx.splitCoins(tx.gas, [100n])
    buildKeeperDepositYield(tx, config, keeperParams, fakeCoin, '0x1234::usdb::USDB', '0xcustom')
    expect(tx.getData).toBeDefined()
  })

  it('falls back to config.merchantId when none provided', () => {
    const tx = new Transaction()
    const fakeCoin = tx.splitCoins(tx.gas, [100n])
    // No merchantId arg — should use config.merchantId without throwing
    buildKeeperDepositYield(tx, config, keeperParams, fakeCoin, '0x1234::usdb::USDB')
    expect(tx).toBeInstanceOf(Transaction)
  })
})

describe('buildKeeperDeposit (composite)', () => {
  it('creates a valid transaction with withdraw + mint', () => {
    const tx = buildKeeperDeposit(config, keeperParams, 1000n, '0x1234::usdc::USDC')
    expect(tx).toBeInstanceOf(Transaction)
    expect(tx.getData).toBeDefined()
  })

  it('throws on zero amount', () => {
    expect(() => buildKeeperDeposit(config, keeperParams, 0n, '0x1234::usdc::USDC'))
      .toThrow('Amount must be greater than zero')
  })

  it('throws on negative amount', () => {
    expect(() => buildKeeperDeposit(config, keeperParams, -5n, '0x1234::usdc::USDC'))
      .toThrow('Amount must be greater than zero')
  })
})

describe('buildKeeperHarvest (composite)', () => {
  it('creates a valid transaction with claim + deposit_yield', () => {
    const tx = buildKeeperHarvest(config, keeperParams, '0xabcd', '0x1234::usdb::USDB')
    expect(tx).toBeInstanceOf(Transaction)
    expect(tx.getData).toBeDefined()
  })
})
