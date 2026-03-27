// packages/sdk/src/types.ts

/** All object IDs are 0x-prefixed hex strings */
export type ObjectId = string

export interface FloatSyncConfig {
  network: 'mainnet' | 'testnet' | 'devnet'
  packageId: ObjectId
  merchantId: ObjectId
  registryId?: ObjectId
  routerConfigId?: ObjectId
  /** Custom gRPC endpoint. Defaults to Mysten public endpoint for the network. */
  grpcUrl?: string
  /** Custom GraphQL endpoint. Defaults to Mysten public endpoint for the network. */
  graphqlUrl?: string
}

export interface PayParams {
  amount: bigint | number
  coin: string           // shorthand ('USDC') or full type ('0x...::mod::TYPE')
  orderId: string        // required for v2 dedup
}

export interface SubscribeParams {
  amountPerPeriod: bigint | number
  periodMs: number
  prepaidPeriods: number
  coin: string
  orderId: string
}

export interface FundParams {
  subscriptionId: ObjectId
  amount: bigint | number
  coin: string
}

export interface RegisterParams {
  brandName: string
  registryId?: ObjectId
}

export interface QueryParams {
  cursor?: string
  limit?: number
  order?: 'asc' | 'desc'
}

export interface TransactionResult {
  tx: import('@mysten/sui/transactions').Transaction
}

export interface ExecutedResult {
  digest: string
  status: 'success' | 'failure'
  events: FloatSyncEventData[]
  gasUsed: bigint
  payment?: { orderId: string; amount: bigint; coinType: string }
  subscription?: { subscriptionId: string; nextDue: number }
  merchant?: { merchantId: string; capId: string }
}

// ── Event types ──

export type FloatSyncEventName =
  | 'payment.received'
  | 'subscription.created'
  | 'subscription.processed'
  | 'subscription.cancelled'
  | 'subscription.funded'
  | 'merchant.registered'
  | 'merchant.paused'
  | 'merchant.unpaused'
  | 'yield.claimed'
  | 'router.mode_changed'
  | 'order.record_removed'
  | '*'

export interface FloatSyncEventData {
  type: FloatSyncEventName
  merchantId?: string
  payer?: string
  amount?: bigint
  orderId?: string
  coinType?: string
  timestamp?: number
  [key: string]: unknown
}

export type EventCallback = (event: FloatSyncEventData) => void
export type Unsubscribe = () => void

// ── Merchant info ──

export interface MerchantInfo {
  merchantId: ObjectId
  owner: string
  brandName: string
  totalReceived: bigint
  idlePrincipal: bigint
  accruedYield: bigint
  activeSubscriptions: number
  paused: boolean
}

export interface SubscriptionInfo {
  subscriptionId: ObjectId
  merchantId: ObjectId
  payer: string
  amountPerPeriod: bigint
  periodMs: number
  nextDue: number
  balance: bigint
}
