// packages/sdk/src/client.ts

import { SuiGrpcClient } from '@mysten/sui/grpc'
import { SuiGraphQLClient } from '@mysten/sui/graphql'
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
import { DEFAULT_GRPC_URLS, DEFAULT_GRAPHQL_URLS } from './constants.js'
import { QUERY_EVENTS } from './events/queries.js'
import type { QueryEventsResult } from './events/queries.js'
import { ValidationError } from './errors.js'
import { IdempotencyGuard } from './idempotency.js'
import { EventStream } from './events/stream.js'
import { detectVersion } from './version.js'
import type { VersionInfo } from './version.js'
import { buildPayOnceV2, buildPayOnce, buildPayOnceRouted } from './transactions/pay.js'
import type { YieldInfo } from './types.js'
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
  private readonly grpcClient: SuiGrpcClient
  private readonly graphqlClient: SuiGraphQLClient
  private readonly idempotency: IdempotencyGuard
  private readonly events: EventStream
  private versionCache?: VersionInfo

  constructor(config: FloatSyncConfig, options?: FloatSyncClientOptions) {
    if (!config.packageId) throw new ValidationError('MISSING_PACKAGE_ID', 'packageId is required')
    if (!config.merchantId) throw new ValidationError('MISSING_MERCHANT_ID', 'merchantId is required')
    if (!config.network) throw new ValidationError('MISSING_NETWORK', 'network is required')

    this.config = config
    this.grpcClient = new SuiGrpcClient({
      baseUrl: config.grpcUrl ?? DEFAULT_GRPC_URLS[config.network],
      network: config.network,
    })
    this.graphqlClient = new SuiGraphQLClient({
      url: config.graphqlUrl ?? DEFAULT_GRAPHQL_URLS[config.network],
      network: config.network,
    })
    this.idempotency = new IdempotencyGuard({ pendingTtlMs: options?.pendingTtlMs })
    this.events = new EventStream(config.packageId)
  }

  get rawClient(): SuiGrpcClient {
    return this.grpcClient
  }

  // ── Version Detection ──

  private async version(): Promise<VersionInfo> {
    if (!this.versionCache) {
      this.versionCache = await detectVersion(this.grpcClient, this.config.packageId)
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
      return { tx: (await buildPayOnceV2(this.grpcClient, this.config, params, sender)) }
      // Note: caller can check idempotency.getCachedResult() for the prior result
    }

    this.idempotency.markPending(key)
    try {
      const ver = await this.version()
      const tx = ver.hasV2
        ? await buildPayOnceV2(this.grpcClient, this.config, params, sender)
        : await buildPayOnce(this.grpcClient, this.config, params, sender)
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
        ? await buildSubscribeV2(this.grpcClient, this.config, params, sender)
        : await buildSubscribe(this.grpcClient, this.config, params, sender)
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
    const tx = await buildFundSubscription(this.grpcClient, this.config, params, sender)
    return { tx }
  }

  /** Build a register_merchant transaction. */
  registerMerchant(params: RegisterParams): TransactionResult {
    return { tx: buildRegisterMerchant(this.config, params) }
  }

  /** Build a claim_yield transaction. Requires MerchantCap. */
  claimYield(merchantCapId: string, coinType?: string): TransactionResult {
    return { tx: buildClaimYield(this.config, merchantCapId, coinType) }
  }

  /**
   * Build a pay_once_routed transaction (StableLayer mode).
   * Routes payment to Vault. Use when router mode = 1.
   */
  async payRouted(params: PayParams, sender: string): Promise<TransactionResult> {
    const key = IdempotencyGuard.key(this.config.merchantId, params.orderId)
    const existing = this.idempotency.check(key)
    if (existing === 'pending') {
      throw new ValidationError('DUPLICATE_PENDING', `Payment for order "${params.orderId}" is already in progress`)
    }

    this.idempotency.markPending(key)
    try {
      const tx = await buildPayOnceRouted(this.grpcClient, this.config, params, sender)
      return { tx }
    } catch (err) {
      this.idempotency.remove(key)
      throw err
    }
  }

  /**
   * Query yield info for a merchant.
   * Combines on-chain MerchantAccount data with vault balance.
   */
  async getYieldInfo(merchantId?: ObjectId): Promise<YieldInfo> {
    const id = merchantId ?? this.config.merchantId
    const merchant = await this.getMerchant(id)

    let vaultBalance = 0n
    if (this.config.vaultId) {
      try {
        const { object } = await this.grpcClient.getObject({
          objectId: this.config.vaultId,
          include: { json: true },
        })
        if (object?.json) {
          const fields = object.json as Record<string, unknown>
          vaultBalance = BigInt(String(fields.balance ?? '0'))
        }
      } catch {
        // Vault query failed — non-fatal
      }
    }

    return {
      idlePrincipal: merchant.idlePrincipal,
      accruedYield: merchant.accruedYield,
      claimableUsdb: merchant.accruedYield, // MVP: same as accruedYield
      estimatedApy: 0, // Calculated by React hook from event history
      vaultBalance,
    }
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
    await this.events.start(this.graphqlClient)
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
    const { object } = await this.grpcClient.getObject({ objectId: id, include: { json: true } })

    if (!object?.json) {
      throw new ValidationError('MERCHANT_NOT_FOUND', `Merchant ${id} not found`)
    }

    const fields = object.json as Record<string, unknown>
    return deserializeMerchant(id, fields)
  }

  /**
   * Fetch subscription info from on-chain state.
   */
  async getSubscription(subscriptionId: ObjectId): Promise<SubscriptionInfo> {
    const { object } = await this.grpcClient.getObject({ objectId: subscriptionId, include: { json: true } })

    if (!object?.json) {
      throw new ValidationError('SUBSCRIPTION_NOT_FOUND', `Subscription ${subscriptionId} not found`)
    }

    const fields = object.json as Record<string, unknown>
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

    const eventType = `${this.config.packageId}::events::PaymentReceivedV2`
    const result = await this.graphqlClient.query<QueryEventsResult>({
      query: QUERY_EVENTS,
      variables: {
        type: eventType,
        after: cursor ?? undefined,
        first: limit,
      },
    })

    if (!result.data) {
      return { events: [], hasNextPage: false }
    }

    const { normalizeEvent } = await import('./events/types.js')
    let events = result.data.events.nodes
      .filter((n) => n.type?.repr && n.contents?.json)
      .map((n) => normalizeEvent(n.type!.repr, n.contents!.json))

    if (payer) {
      events = events.filter((e) => e.payer === payer)
    }

    if (order === 'desc') {
      events.reverse()
    }

    return {
      events,
      nextCursor: result.data.events.pageInfo.endCursor ?? undefined,
      hasNextPage: result.data.events.pageInfo.hasNextPage,
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
