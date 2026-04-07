import { Transaction } from '@mysten/sui/transactions'
import type { BaleenPayConfig, RegisterParams, WithdrawParams } from '../types.js'
import { resolveCoin, coinTypeArg } from '../coins/registry.js'

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

export function buildMerchantWithdraw(
  config: BaleenPayConfig,
  params: WithdrawParams,
): Transaction {
  if (params.amount <= 0n) throw new Error('Amount must be greater than zero')
  if (!config.vaultId) throw new Error('vaultId is required in config for merchant_withdraw')

  const resolved = resolveCoin(config.network, params.coinType)
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::router::merchant_withdraw`,
    typeArguments: [coinTypeArg(resolved.type)],
    arguments: [
      tx.object(params.merchantCapId),
      tx.object(config.merchantId),
      tx.object(config.vaultId),
      tx.pure.u64(params.amount),
    ],
  })
  return tx
}
