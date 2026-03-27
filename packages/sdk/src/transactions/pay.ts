import { Transaction } from '@mysten/sui/transactions'
import type { SuiGrpcClient } from '@mysten/sui/grpc'
import type { FloatSyncConfig, PayParams } from '../types.js'
import { resolveCoin, coinTypeArg } from '../coins/registry.js'
import { prepareCoin } from '../coins/helper.js'
import { CLOCK_OBJECT_ID, ORDER_ID_REGEX } from '../constants.js'

const PII_PATTERNS = [
  /^[^@\s]+@[^@\s]+\.[^@\s]+$/,    // email
  /^\+?\d{7,15}$/,                    // phone
]

function validateOrderId(orderId: string): void {
  if (!ORDER_ID_REGEX.test(orderId)) {
    throw new Error(
      `Invalid orderId "${orderId}": must be 1-64 ASCII printable characters (0x21-0x7E)`
    )
  }
  for (const pattern of PII_PATTERNS) {
    if (pattern.test(orderId)) {
      throw new Error(
        `orderId "${orderId}" looks like PII (email/phone). Use an opaque identifier instead.`
      )
    }
  }
}

/**
 * Build a pay_once_v2 PTB.
 * Handles coin resolution, merge/split, and orderId validation.
 */
export async function buildPayOnceV2(
  client: SuiGrpcClient,
  config: FloatSyncConfig,
  params: PayParams,
  sender: string,
): Promise<Transaction> {
  validateOrderId(params.orderId)

  const coinConfig = resolveCoin(config.network, params.coin)
  const amount = BigInt(params.amount)

  if (amount <= 0n) {
    throw new Error('Payment amount must be greater than zero')
  }

  const tx = new Transaction()
  const paymentCoin = await prepareCoin(tx, client, sender, coinConfig.type, amount)

  tx.moveCall({
    target: `${config.packageId}::payment::pay_once_v2`,
    typeArguments: [coinTypeArg(coinConfig.type)],
    arguments: [
      tx.object(config.merchantId),
      paymentCoin,
      tx.pure.string(params.orderId),
      tx.object(CLOCK_OBJECT_ID),
    ],
  })

  return tx
}

/**
 * Build a legacy pay_once PTB (v1, no orderId dedup).
 */
export async function buildPayOnce(
  client: SuiGrpcClient,
  config: FloatSyncConfig,
  params: Omit<PayParams, 'orderId'>,
  sender: string,
): Promise<Transaction> {
  const coinConfig = resolveCoin(config.network, params.coin)
  const amount = BigInt(params.amount)

  if (amount <= 0n) {
    throw new Error('Payment amount must be greater than zero')
  }

  const tx = new Transaction()
  const paymentCoin = await prepareCoin(tx, client, sender, coinConfig.type, amount)

  tx.moveCall({
    target: `${config.packageId}::payment::pay_once`,
    typeArguments: [coinTypeArg(coinConfig.type)],
    arguments: [
      tx.object(config.merchantId),
      paymentCoin,
      tx.object(CLOCK_OBJECT_ID),
    ],
  })

  return tx
}
