import { Transaction } from '@mysten/sui/transactions'
import type { TransactionArgument } from '@mysten/sui/transactions'
import type { BaleenPayConfig, KeeperParams } from '../types.js'
import { StableLayerClient } from '../stablelayer/client.js'
import { STABLELAYER_CONFIG } from '../stablelayer/constants.js'
import { coinTypeArg } from '../coins/registry.js'

export function buildKeeperWithdraw(
  config: BaleenPayConfig,
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
      tx.object('0x6'), // Clock
    ],
  })
  return tx
}

export function buildKeeperDepositYield(
  tx: Transaction,
  config: BaleenPayConfig,
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

/**
 * Composite: keeper_withdraw → stable_layer::mint → farm::receive → keeper_deposit_to_farm.
 *
 * Single PTB that atomically:
 * 1. Withdraws USDC from vault
 * 2. Mints Stablecoin via StableLayer (hot-potato Loan consumed by farm::receive)
 * 3. Deposits Stablecoin receipt into StablecoinVault
 * 4. Updates merchant accounting (idle_principal → farming_principal)
 */
export function buildKeeperDeposit(
  config: BaleenPayConfig,
  keeper: KeeperParams,
  amount: bigint,
  coinType: string,
  merchantId?: string,
): Transaction {
  if (amount <= 0n) throw new Error('Amount must be greater than zero')
  if (!keeper.stablecoinVaultId) {
    throw new Error('stablecoinVaultId is required in keeper params for deposit')
  }

  const network = config.network as 'testnet' | 'mainnet'
  const slConfig = STABLELAYER_CONFIG[network]
  const stableClient = new StableLayerClient(slConfig)

  const tx = new Transaction()

  // Step 1: Withdraw USDC from Vault
  const usdcCoin = tx.moveCall({
    target: `${config.packageId}::router::keeper_withdraw`,
    typeArguments: [coinTypeArg(coinType)],
    arguments: [
      tx.object(keeper.adminCapId),
      tx.object(keeper.vaultId),
      tx.pure.u64(amount),
      tx.object('0x6'), // Clock
    ],
  })

  // Step 2: Mint Stablecoin + farm::receive (consumes Loan hot-potato)
  const stablecoin = stableClient.buildMintTx({ tx, usdcCoin })

  // Step 3: Deposit Stablecoin into StablecoinVault + update merchant accounting
  tx.moveCall({
    target: `${config.packageId}::router::keeper_deposit_to_farm`,
    typeArguments: [slConfig.stablecoinType],
    arguments: [
      tx.object(keeper.adminCapId),
      tx.object(merchantId ?? config.merchantId),
      tx.object(keeper.stablecoinVaultId),
      stablecoin,
    ],
  })

  return tx
}

/**
 * Composite: farm::claim → keeper_deposit_yield.
 *
 * Claims USDB yield from the farm, then deposits it into the YieldVault
 * and credits the merchant's accrued_yield.
 */
export function buildKeeperHarvest(
  config: BaleenPayConfig,
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
