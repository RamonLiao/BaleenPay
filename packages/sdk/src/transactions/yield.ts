import { Transaction } from '@mysten/sui/transactions'
import type { BaleenPayConfig } from '../types.js'
import { resolveCoin, coinTypeArg } from '../coins/registry.js'

/**
 * Build claim_yield_v2 PTB (router module, with YieldVault).
 * Requires yieldVaultId in config and coinType.
 */
export function buildClaimYield(
  config: BaleenPayConfig,
  merchantCapId: string,
  coinType: string,
): Transaction {
  if (!config.yieldVaultId) {
    throw new Error('yieldVaultId is required in config for claim_yield')
  }
  const resolved = resolveCoin(config.network, coinType)
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::router::claim_yield_v2`,
    typeArguments: [coinTypeArg(resolved.type)],
    arguments: [
      tx.object(merchantCapId),
      tx.object(config.merchantId),
      tx.object(config.yieldVaultId),
    ],
  })
  return tx
}
