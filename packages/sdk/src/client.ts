// packages/sdk/src/client.ts

import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc'
import type {
  FloatSyncConfig,
  PayParams,
  SubscribeParams,
  FundParams,
  RegisterParams,
  QueryParams,
  TransactionResult,
  MerchantInfo,
  SubscriptionInfo,
  FloatSyncEventName,
  FloatSyncEventData,
  EventCallback,
  Unsubscribe,
  ObjectId,
} from './types.js'
import { DEFAULT_RPC_URLS } from './constants.js'
import { ValidationError } from './errors.js'
import { IdempotencyGuard } from './idempotency.js'
import { EventStream } from './events/stream.js'
import { detectVersion } from './version.js'
import type { VersionInfo } from './version.js'
import { buildPayOnceV2, buildPayOnce } from './transactions/pay.js'
import { buildSubscribeV2, buildSubscribe } from './transactions/subscribe.js'
import { buildRegisterMerchant, buildSelfPause, buildSelfUnpause } from './transactions/merchant.js'
import { buildClaimYield } from './transactions/yield.js'
import {
  buildProcessSubscription,
  buildCancelSubscription,
  buildFundSubscription,
} from './transactions/subscription.js'

export interface FloatSyncClientOptions {
  /** Pending idempotency TTL in ms. Default: 60000 */
  pendingTtlMs?: number
}

export class FloatSync {
  readonly config: FloatSyncConfig
  readonly suiClient: SuiJsonRpcClient
  private readonly idempotency: IdempotencyGuard
  private readonly events: EventStream
  private versionCache?: VersionInfo

  constructor(config: FloatSyncConfig, options?: FloatSyncClientOptions) {
    if (!config.packageId) throw new ValidationError('MISSING_PACKAGE_ID', 'packageId is required')
    if (!config.merchantId) throw new ValidationError('MISSING_MERCHANT_ID', 'merchantId is required')
    if (!config.network) throw new ValidationError('MISSING_NETWORK', 'network is required')

    this.config = config
    this.suiClient = new SuiJsonRpcClient({
      url: config.rpcUrl ?? DEFAULT_RPC_URLS[config.network] ?? getJsonRpcFullnodeUrl(config.network),
      network: config.network,
    })
    this.idempotency = new IdempotencyGuard({ pendingTtlMs: options?.pendingTtlMs })
    this.events = new EventStream(config.packageId)
  }

  // ── Version Detection ──

  private async version(): Promise<VersionInfo> {
    if (!this.versionCache) {
      this.versionCache = await detectVersion(this.suiClient, this.config.packageId)
    }
    return this.versionCache
  }

  // ── Payment Methods ──

  /**
   * Build a pay_once transaction. Uses v2 (with orderId dedup) when available.
   */
  async pay(params: PayParams, sender: string): Promise<TransactionResult> {
    const key = IdempotencyGuard.key(this.config.merchantId, params.orderId)
    const existing = this.idempotency.check(key)
    if (existing === 'pending') {
      throw new ValidationError('DUPLICATE_PENDING', `Payment for order "${params.orderId}" is already in progress`)
    }
    if (existing) {
      return { tx: (await buildPayOnceV2(this.suiClient, this.config, params, sender)) }
      // Note: caller can check idempotency.getCachedResult() for the prior result
    }

    this.idempotency.markPending(key)
    try {
      const ver = await this.version()
      const tx = ver.hasV2
        ? await buildPayOnceV2(this.suiClient, this.config, params, sender)
        : await buildPayOnce(this.suiClient, this.config, params, sender)
      return { tx }
    } catch (err) {
      this.idempotency.remove(key)
      throw err
    }
  }

  /**
   * Build a subscribe transaction. Uses v2 when available.
   */
  async subscribe(params: SubscribeParams, sender: string): Promise<TransactionResult> {
    const key = IdempotencyGuard.key(this.config.merchantId, params.orderId)
    const existing = this.idempotency.check(key)
    if (existing === 'pending') {
      throw new ValidationError('DUPLICATE_PENDING', `Subscription for order "${params.orderId}" is already in progress`)
    }

    this.idempotency.markPending(key)
    try {
      const ver = await this.version()
      const tx = ver.hasV2
        ? await buildSubscribeV2(this.suiClient, this.config, params, sender)
        : await buildSubscribe(this.suiClient, this.config, params, sender)
      return { tx }
    } catch (err) {
      this.idempotency.remove(key)
      throw err
    }
  }

  /** Build a process_subscription transaction (anyone can call). */
  processSubscription(subscriptionId: ObjectId, coinType: string): TransactionResult {
    return { tx: buildProcessSubscription(this.config, subscriptionId, coinType) }
  }

  /** Build a cancel_subscription transaction (payer only). */
  cancelSubscription(subscriptionId: ObjectId, coinType: string): TransactionResult {
    return { tx: buildCancelSubscription(this.config, subscriptionId, coinType) }
  }

  /** Build a fund_subscription transaction. */
  async fundSubscription(params: FundParams, sender: string): Promise<TransactionResult> {
    const tx = await buildFundSubscription(this.suiClient, this.config, params, sender)
    return { tx }
  }

  /** Build a register_merchant transaction. */
  registerMerchant(params: RegisterParams): TransactionResult {
    return { tx: buildRegisterMerchant(this.config, params) }
  }

  /** Build a claim_yield transaction. Requires MerchantCap. */
  claimYield(merchantCapId: string): TransactionResult {
    return { tx: buildClaimYield(this.config, merchantCapId) }
  }

  /** Build a self_pause transaction. Requires MerchantCap. */
  selfPause(merchantCapId: string): TransactionResult {
    return { tx: buildSelfPause(this.config, merchantCapId) }
  }

  /** Build a self_unpause transaction. Requires MerchantCap. */
  selfUnpause(merchantCapId: string): TransactionResult {
    return { tx: buildSelfUnpause(this.config, merchantCapId) }
  }

  // ── Idempotency ──

  /** Access the idempotency guard for advanced usage (e.g., markCompleted after execution). */
  get idempotencyGuard(): IdempotencyGuard {
    return this.idempotency
  }

  // ── Events ──

  /** Subscribe to FloatSync on-chain events. */
  on(event: FloatSyncEventName, callback: EventCallback, filter?: Record<string, unknown>): Unsubscribe {
    return this.events.on(event, callback, filter)
  }

  /** Start listening to on-chain events via WebSocket. */
  async startEventStream(): Promise<void> {
    await this.events.start(this.suiClient)
  }

  /** Stop listening to on-chain events. */
  stopEventStream(): void {
    this.events.stop()
  }

  // ── Query Methods ──

  /**
   * Fetch merchant account info from on-chain state.
   */
  async getMerchant(merchantId?: ObjectId): Promise<MerchantInfo> {
    const id = merchantId ?? this.config.merchantId
    const obj = await this.suiClient.getObject({
      id,
      options: { showContent: true },
    })

    if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') {
      throw new ValidationError('MERCHANT_NOT_FOUND', `Merchant ${id} not found`)
    }

    const fields = obj.data.content.fields as Record<string, unknown>
    return deserializeMerchant(id, fields)
  }

  /**
   * Fetch subscription info from on-chain state.
   */
  async getSubscription(subscriptionId: ObjectId): Promise<SubscriptionInfo> {
    const obj = await this.suiClient.getObject({
      id: subscriptionId,
      options: { showContent: true },
    })

    if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') {
      throw new ValidationError('SUBSCRIPTION_NOT_FOUND', `Subscription ${subscriptionId} not found`)
    }

    const fields = obj.data.content.fields as Record<string, unknown>
    return deserializeSubscription(subscriptionId, fields)
  }

  /**
   * Query payment history via on-chain events.
   * Returns normalized v1/v2 events.
   */
  async getPaymentHistory(params?: QueryParams & { payer?: string }): Promise<{
    events: FloatSyncEventData[]
    nextCursor?: string
    hasNextPage: boolean
  }> {
    const { cursor, limit = 20, order = 'desc', payer } = params ?? {}

    // Query both v1 and v2 payment events
    const eventType = `${this.config.packageId}::events::PaymentReceivedV2`
    const result = await this.suiClient.queryEvents({
      query: { MoveEventType: eventType },
      cursor: cursor ? JSON.parse(cursor) : undefined,
      limit,
      order: order === 'asc' ? 'ascending' : 'descending',
    })

    const { normalizeEvent } = await import('./events/types.js')
    let events = result.data.map((e) =>
      normalizeEvent(e.type, e.parsedJson as Record<string, unknown>),
    )

    // Client-side payer filter
    if (payer) {
      events = events.filter((e) => e.payer === payer)
    }

    return {
      events,
      nextCursor: result.nextCursor ? JSON.stringify(result.nextCursor) : undefined,
      hasNextPage: result.hasNextPage,
    }
  }
}

// ── Deserializers ──

function deserializeMerchant(id: string, fields: Record<string, unknown>): MerchantInfo {
  return {
    merchantId: id,
    owner: String(fields.owner ?? ''),
    brandName: String(fields.brand_name ?? ''),
    totalReceived: BigInt(String(fields.total_received ?? '0')),
    idlePrincipal: BigInt(String(fields.idle_principal ?? '0')),
    accruedYield: BigInt(String(fields.accrued_yield ?? '0')),
    activeSubscriptions: Number(fields.active_subscriptions ?? 0),
    paused: Boolean(fields.paused),
  }
}

function deserializeSubscription(id: string, fields: Record<string, unknown>): SubscriptionInfo {
  return {
    subscriptionId: id,
    merchantId: String(fields.merchant_id ?? ''),
    payer: String(fields.payer ?? ''),
    amountPerPeriod: BigInt(String(fields.amount_per_period ?? '0')),
    periodMs: Number(fields.period_ms ?? 0),
    nextDue: Number(fields.next_due ?? 0),
    balance: BigInt(String(fields.balance ?? '0')),
  }
}
