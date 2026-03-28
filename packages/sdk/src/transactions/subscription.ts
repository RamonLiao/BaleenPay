import { Transaction } from '@mysten/sui/transactions'
import type { SuiGrpcClient } from '@mysten/sui/grpc'
import type { BaleenPayConfig, FundParams, ObjectId } from '../types.js'
import { resolveCoin, coinTypeArg } from '../coins/registry.js'
import { prepareCoin } from '../coins/helper.js'
import { CLOCK_OBJECT_ID } from '../constants.js'

export function buildProcessSubscription(
  config: BaleenPayConfig,
  subscriptionId: ObjectId,
  coinType: string,
): Transaction {
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::payment::process_subscription`,
    typeArguments: [coinType],
    arguments: [
      tx.object(config.merchantId),
      tx.object(subscriptionId),
      tx.object(CLOCK_OBJECT_ID),
    ],
  })
  return tx
}

export function buildCancelSubscription(
  config: BaleenPayConfig,
  subscriptionId: ObjectId,
  coinType: string,
): Transaction {
  const tx = new Transaction()
  tx.moveCall({
    target: `${config.packageId}::payment::cancel_subscription`,
    typeArguments: [coinType],
    arguments: [
      tx.object(config.merchantId),
      tx.object(subscriptionId),
    ],
  })
  return tx
}

export async function buildFundSubscription(
  client: SuiGrpcClient,
  config: BaleenPayConfig,
  params: FundParams,
  sender: string,
): Promise<Transaction> {
  const coinConfig = resolveCoin(config.network, params.coin)
  const amount = BigInt(params.amount)

  const tx = new Transaction()
  const fundCoin = await prepareCoin(tx, client, sender, coinConfig.type, amount)

  tx.moveCall({
    target: `${config.packageId}::payment::fund_subscription`,
    typeArguments: [coinTypeArg(coinConfig.type)],
    arguments: [
      tx.object(config.merchantId),
      tx.object(params.subscriptionId),
      fundCoin,
    ],
  })

  return tx
}
