// packages/sdk/src/events/types.ts

import type { BaleenPayEventData, BaleenPayEventName } from '../types.js'

/** Maps Move event struct name → SDK event name */
export const EVENT_TYPE_MAP: Record<string, BaleenPayEventName> = {
  PaymentReceived: 'payment.received',
  PaymentReceivedV2: 'payment.received',
  SubscriptionCreated: 'subscription.created',
  SubscriptionCreatedV2: 'subscription.created',
  SubscriptionProcessed: 'subscription.processed',
  SubscriptionCancelled: 'subscription.cancelled',
  SubscriptionFunded: 'subscription.funded',
  MerchantRegistered: 'merchant.registered',
  MerchantPaused: 'merchant.paused',
  MerchantUnpaused: 'merchant.unpaused',
  YieldClaimed: 'yield.claimed',
  RouterModeChanged: 'router.mode_changed',
  OrderRecordRemoved: 'order.record_removed',
}

const V2_EVENTS = new Set(['PaymentReceivedV2', 'SubscriptionCreatedV2'])

/**
 * Extract the struct name from a full Move type string.
 * e.g. `0xabc::events::PaymentReceivedV2` → `PaymentReceivedV2`
 */
function extractStructName(moveType: string): string {
  const parts = moveType.split('::')
  return parts[parts.length - 1]
}

/**
 * Normalize an on-chain Move event into a BaleenPayEventData.
 */
export function normalizeEvent(
  moveType: string,
  parsedJson: Record<string, unknown>,
): BaleenPayEventData {
  const structName = extractStructName(moveType)
  const eventName = EVENT_TYPE_MAP[structName]

  if (!eventName) {
    return { type: '*' as BaleenPayEventName, ...parsedJson }
  }

  const isV2 = V2_EVENTS.has(structName)

  const base: BaleenPayEventData = {
    type: eventName,
  }

  // Copy known fields, converting amounts to bigint
  if (parsedJson.merchant_id !== undefined) base.merchantId = String(parsedJson.merchant_id)
  if (parsedJson.payer !== undefined) base.payer = String(parsedJson.payer)
  if (parsedJson.timestamp !== undefined) base.timestamp = Number(parsedJson.timestamp)

  // Amount fields → bigint
  if (parsedJson.amount !== undefined) base.amount = BigInt(parsedJson.amount as string | number)
  if (parsedJson.amount_per_period !== undefined)
    base.amountPerPeriod = BigInt(parsedJson.amount_per_period as string | number)

  // V2 fields
  if (isV2) {
    base.orderId = parsedJson.order_id !== undefined ? String(parsedJson.order_id) : undefined
    base.coinType = parsedJson.coin_type !== undefined ? String(parsedJson.coin_type) : undefined
  } else {
    base.orderId = undefined
    base.coinType = undefined
  }

  // Subscription-specific fields
  if (parsedJson.subscription_id !== undefined)
    base.subscriptionId = String(parsedJson.subscription_id)
  if (parsedJson.period_ms !== undefined) base.periodMs = Number(parsedJson.period_ms)
  if (parsedJson.prepaid_periods !== undefined)
    base.prepaidPeriods = Number(parsedJson.prepaid_periods)

  return base
}
