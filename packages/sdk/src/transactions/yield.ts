import { Transaction } from '@mysten/sui/transactions'
import type { FloatSyncConfig } from '../types.js'

export function buildClaimYield(
  config: FloatSyncConfig,
  merchantCapId: string,
): Transaction {
  if (!config.routerConfigId) {
    throw new Error('routerConfigId is required for claim_yield')
  }

  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::router::claim_yield`,
    arguments: [
      tx.object(merchantCapId),
      tx.object(config.merchantId),
      tx.object(config.routerConfigId),
    ],
  })
  return tx
}
