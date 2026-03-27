import { Transaction } from '@mysten/sui/transactions'
import type { SuiGrpcClient } from '@mysten/sui/grpc'
import type { FloatSyncConfig, SubscribeParams } from '../types.js'
import { resolveCoin, coinTypeArg } from '../coins/registry.js'
import { prepareCoin } from '../coins/helper.js'
import { CLOCK_OBJECT_ID, ORDER_ID_REGEX } from '../constants.js'

const MAX_PREPAID_PERIODS = 1000

function validateSubscribeParams(params: SubscribeParams): void {
  if (!ORDER_ID_REGEX.test(params.orderId)) {
    throw new Error(`Invalid orderId: must be 1-64 ASCII printable characters`)
  }
  if (params.prepaidPeriods > MAX_PREPAID_PERIODS) {
    throw new Error(`prepaidPeriods (${params.prepaidPeriods}) exceeds maximum (${MAX_PREPAID_PERIODS})`)
  }
  if (params.prepaidPeriods <= 0) {
    throw new Error('prepaidPeriods must be greater than zero')
  }
  if (Number(params.amountPerPeriod) <= 0) {
    throw new Error('amountPerPeriod must be greater than zero')
  }
  if (params.periodMs <= 0) {
    throw new Error('periodMs must be greater than zero')
  }
}

export async function buildSubscribeV2(
  client: SuiGrpcClient,
  config: FloatSyncConfig,
  params: SubscribeParams,
  sender: string,
): Promise<Transaction> {
  validateSubscribeParams(params)

  const coinConfig = resolveCoin(config.network, params.coin)
  const amountPerPeriod = BigInt(params.amountPerPeriod)
  const totalRequired = amountPerPeriod * BigInt(params.prepaidPeriods)

  const tx = new Transaction()
  const paymentCoin = await prepareCoin(tx, client, sender, coinConfig.type, totalRequired)

  tx.moveCall({
    target: `${config.packageId}::payment::subscribe_v2`,
    typeArguments: [coinTypeArg(coinConfig.type)],
    arguments: [
      tx.object(config.merchantId),
      paymentCoin,
      tx.pure.u64(amountPerPeriod),
      tx.pure.u64(BigInt(params.periodMs)),
      tx.pure.u64(BigInt(params.prepaidPeriods)),
      tx.pure.string(params.orderId),
      tx.object(CLOCK_OBJECT_ID),
    ],
  })

  return tx
}

export async function buildSubscribe(
  client: SuiGrpcClient,
  config: FloatSyncConfig,
  params: Omit<SubscribeParams, 'orderId'>,
  sender: string,
): Promise<Transaction> {
  const coinConfig = resolveCoin(config.network, params.coin)
  const amountPerPeriod = BigInt(params.amountPerPeriod)
  const totalRequired = amountPerPeriod * BigInt(params.prepaidPeriods)

  const tx = new Transaction()
  const paymentCoin = await prepareCoin(tx, client, sender, coinConfig.type, totalRequired)

  tx.moveCall({
    target: `${config.packageId}::payment::subscribe`,
    typeArguments: [coinTypeArg(coinConfig.type)],
    arguments: [
      tx.object(config.merchantId),
      paymentCoin,
      tx.pure.u64(amountPerPeriod),
      tx.pure.u64(BigInt(params.periodMs)),
      tx.pure.u64(BigInt(params.prepaidPeriods)),
      tx.object(CLOCK_OBJECT_ID),
    ],
  })

  return tx
}
