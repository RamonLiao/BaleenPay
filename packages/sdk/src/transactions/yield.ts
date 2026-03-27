import { Transaction } from '@mysten/sui/transactions'
import type { FloatSyncConfig } from '../types.js'
import { resolveCoin, coinTypeArg } from '../coins/registry.js'

/**
 * Build claim_yield PTB.
 * If config has yieldVaultId AND coinType is provided, uses claim_yield_v2 (router module, with YieldVault).
 * Otherwise falls back to legacy claim_yield (merchant module, returns u64 only).
 *
 * Note: claim_yield_v2 is in the router module (to avoid circular dependency).
 */
export function buildClaimYield(
  config: FloatSyncConfig,
  merchantCapId: string,
  coinType?: string,
): Transaction {
  // v2 path: use router::claim_yield_v2 with YieldVault
  if (config.yieldVaultId && coinType) {
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

  // Legacy: if yieldVaultId is missing but coinType provided, error
  if (!config.yieldVaultId && coinType) {
    throw new Error('yieldVaultId is required for claim_yield with coinType')
  }

  // Legacy path: merchant::claim_yield
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::merchant::claim_yield`,
    arguments: [
      tx.object(merchantCapId),
      tx.object(config.merchantId),
    ],
  })
  return tx
}
