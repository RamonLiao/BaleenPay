import { Transaction } from '@mysten/sui/transactions'
import type { TransactionArgument } from '@mysten/sui/transactions'
import type { FloatSyncConfig, KeeperParams } from '../types.js'
import { StableLayerClient } from '../stablelayer/client.js'
import { STABLELAYER_CONFIG } from '../stablelayer/constants.js'
import { coinTypeArg } from '../coins/registry.js'

export function buildKeeperWithdraw(
  config: FloatSyncConfig,
  keeper: KeeperParams,
  amount: bigint,
  coinType: string,
): Transaction {
  if (amount <= 0n) throw new Error('Amount must be greater than zero')

  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::router::keeper_withdraw`,
    typeArguments: [coinTypeArg(coinType)],
    arguments: [
      tx.object(keeper.adminCapId),
      tx.object(keeper.vaultId),
      tx.pure.u64(amount),
    ],
  })
  return tx
}

export function buildKeeperDepositYield(
  tx: Transaction,
  config: FloatSyncConfig,
  keeper: KeeperParams,
  yieldCoin: TransactionArgument,
  yieldCoinType: string,
  merchantId?: string,
): void {
  tx.moveCall({
    target: `${config.packageId}::router::keeper_deposit_yield`,
    typeArguments: [coinTypeArg(yieldCoinType)],
    arguments: [
      tx.object(keeper.adminCapId),
      tx.object(keeper.yieldVaultId),
      tx.object(merchantId ?? config.merchantId),
      yieldCoin,
    ],
  })
}

export function buildKeeperDeposit(
  config: FloatSyncConfig,
  keeper: KeeperParams,
  amount: bigint,
  coinType: string,
): Transaction {
  if (amount <= 0n) throw new Error('Amount must be greater than zero')

  const network = config.network as 'testnet' | 'mainnet'
  const slConfig = STABLELAYER_CONFIG[network]
  const stableClient = new StableLayerClient(slConfig)

  const tx = new Transaction()

  const usdcCoin = tx.moveCall({
    target: `${config.packageId}::router::keeper_withdraw`,
    typeArguments: [coinTypeArg(coinType)],
    arguments: [
      tx.object(keeper.adminCapId),
      tx.object(keeper.vaultId),
      tx.pure.u64(amount),
    ],
  })

  stableClient.buildMintTx({ tx, usdcCoin })

  return tx
}

export function buildKeeperHarvest(
  config: FloatSyncConfig,
  keeper: KeeperParams,
  merchantId: string,
  yieldCoinType: string,
): Transaction {
  const network = config.network as 'testnet' | 'mainnet'
  const slConfig = STABLELAYER_CONFIG[network]
  const stableClient = new StableLayerClient(slConfig)

  const tx = new Transaction()

  const usdbCoin = stableClient.buildClaimTx({ tx })
  buildKeeperDepositYield(tx, config, keeper, usdbCoin, yieldCoinType, merchantId)

  return tx
}
