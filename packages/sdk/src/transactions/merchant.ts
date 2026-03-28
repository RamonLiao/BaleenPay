import { Transaction } from '@mysten/sui/transactions'
import type { BaleenPayConfig, RegisterParams } from '../types.js'

export function buildRegisterMerchant(
  config: BaleenPayConfig,
  params: RegisterParams,
): Transaction {
  const tx = new Transaction()
  const registryId = params.registryId ?? config.registryId
  if (!registryId) {
    throw new Error('registryId is required (provide in config or params)')
  }

  tx.moveCall({
    target: `${config.packageId}::merchant::register_merchant`,
    arguments: [
      tx.object(registryId),
      tx.pure.string(params.brandName),
    ],
  })

  return tx
}

export function buildSelfPause(
  config: BaleenPayConfig,
  merchantCapId: string,
): Transaction {
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::merchant::self_pause`,
    arguments: [
      tx.object(merchantCapId),
      tx.object(config.merchantId),
    ],
  })
  return tx
}

export function buildSelfUnpause(
  config: BaleenPayConfig,
  merchantCapId: string,
): Transaction {
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::merchant::self_unpause`,
    arguments: [
      tx.object(merchantCapId),
      tx.object(config.merchantId),
    ],
  })
  return tx
}
