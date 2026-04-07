import { Transaction, type TransactionObjectArgument } from '@mysten/sui/transactions'
import type { BaleenPayConfig, RedeemParams } from '../types.js'
import { StableLayerClient } from '../stablelayer/client.js'
import { STABLELAYER_CONFIG } from '../stablelayer/constants.js'

/**
 * Composite PTB: take_stablecoin → request_burn → farm::pay → fulfill_burn → transfer USDC.
 *
 * Single SDK call for merchant to redeem farming principal back to USDC.
 * Web2 devs call this; SDK handles all PTB complexity.
 */
export function buildMerchantRedeem(
  config: BaleenPayConfig,
  params: RedeemParams,
): Transaction {
  if (params.amount <= 0n) throw new Error('Amount must be greater than zero')
  if (!config.stablecoinVaultId) {
    throw new Error('stablecoinVaultId is required in config for redeem')
  }

  const network = config.network as 'testnet' | 'mainnet'
  const slConfig = STABLELAYER_CONFIG[network]
  const stableClient = new StableLayerClient(slConfig)

  const tx = new Transaction()

  // Step 1: Take Stablecoin from BaleenPay's StablecoinVault
  const stablecoinCoin = tx.moveCall({
    target: `${config.packageId}::router::take_stablecoin`,
    typeArguments: [slConfig.stablecoinType],
    arguments: [
      tx.object(params.merchantCapId),
      tx.object(config.merchantId),
      tx.object(config.stablecoinVaultId),
      tx.pure.u64(params.amount),
    ],
  })

  // Steps 2-4: StableLayer burn flow (request_burn → farm::pay → fulfill_burn)
  const usdcCoin = stableClient.buildRedeemTx({ tx, stablecoinCoin })

  // Step 5: Transfer USDC to merchant wallet
  tx.transferObjects([usdcCoin as TransactionObjectArgument], tx.pure.address(params.recipientAddress))

  return tx
}
