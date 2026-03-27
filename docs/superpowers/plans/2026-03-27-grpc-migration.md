# gRPC Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all `SuiJsonRpcClient` (JSON-RPC) usage with `SuiGrpcClient` (gRPC) + `SuiGraphQLClient` (GraphQL for events) before April 2026 JSON-RPC removal.

**Architecture:** gRPC is primary transport for object/coin/function queries. GraphQL handles event queries (history + polling) since gRPC has no `queryEvents` equivalent. Both clients are private with a `rawClient` escape hatch.

**Tech Stack:** `@mysten/sui@^2.8.0` (already installed at 2.11.0) — subpath exports `@mysten/sui/grpc`, `@mysten/sui/graphql`, `@mysten/sui/transactions`

**Spec:** `docs/superpowers/specs/2026-03-27-grpc-migration-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `packages/sdk/src/types.ts` | Modify | `FloatSyncConfig`: remove `rpcUrl`, add `grpcUrl?` + `graphqlUrl?` |
| `packages/sdk/src/constants.ts` | Modify | Replace `DEFAULT_RPC_URLS` with `DEFAULT_GRPC_URLS` + `DEFAULT_GRAPHQL_URLS` |
| `packages/sdk/src/coins/helper.ts` | Modify | `SuiJsonRpcClient` → `SuiGrpcClient`, `getCoins` → `listCoins` |
| `packages/sdk/src/coins/validator.ts` | Modify | `SuiJsonRpcClient` → `SuiGrpcClient`, `getCoinMetadata` response shape |
| `packages/sdk/src/transactions/pay.ts` | Modify | Type import only: `SuiJsonRpcClient` → `SuiGrpcClient` |
| `packages/sdk/src/transactions/subscribe.ts` | Modify | Type import only: `SuiJsonRpcClient` → `SuiGrpcClient` |
| `packages/sdk/src/transactions/subscription.ts` | Modify | Type import only: `SuiJsonRpcClient` → `SuiGrpcClient` |
| `packages/sdk/src/version.ts` | Modify | `getNormalizedMoveModule` → `getMoveFunction` try/catch |
| `packages/sdk/src/events/stream.ts` | Modify | `SuiJsonRpcClient` → `SuiGraphQLClient`, `queryEvents` → GraphQL query |
| `packages/sdk/src/events/queries.ts` | Create | GraphQL query string constant for event queries |
| `packages/sdk/src/client.ts` | Modify | Constructor, query methods, `rawClient` getter |
| `packages/sdk/src/index.ts` | Modify | Add `DEFAULT_GRPC_URLS`, `DEFAULT_GRAPHQL_URLS` exports |
| `packages/sdk/test/client.test.ts` | Modify | Mock `@mysten/sui/grpc` + `@mysten/sui/graphql` |
| `packages/sdk/test/integration.test.ts` | Modify | Same mock migration |
| `packages/sdk/test/monkey.test.ts` | Modify | Same mock migration |
| `apps/demo/lib/config.ts` | Verify | No `rpcUrl` used — no change needed |

---

## Task 1: Types + Constants (foundation)

**Files:**
- Modify: `packages/sdk/src/types.ts:6-14`
- Modify: `packages/sdk/src/constants.ts:3-9`
- Modify: `packages/sdk/src/index.ts:21`

- [ ] **Step 1: Update `FloatSyncConfig` in types.ts**

Replace the `rpcUrl` field with `grpcUrl` and `graphqlUrl`:

```ts
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
```

- [ ] **Step 2: Update constants.ts**

Replace `DEFAULT_RPC_URLS` with two new constants:

```ts
export const DEFAULT_GRPC_URLS: Record<string, string> = {
  mainnet: 'https://sui-mainnet.mystenlabs.com',
  testnet: 'https://sui-testnet.mystenlabs.com',
  devnet: 'https://sui-devnet.mystenlabs.com',
}

export const DEFAULT_GRAPHQL_URLS: Record<string, string> = {
  mainnet: 'https://sui-mainnet.mystenlabs.com/graphql',
  testnet: 'https://sui-testnet.mystenlabs.com/graphql',
  devnet: 'https://sui-devnet.mystenlabs.com/graphql',
}
```

- [ ] **Step 3: Update index.ts exports**

Replace `CLOCK_OBJECT_ID` line with:

```ts
export { ABORT_CODE_MAP, CLOCK_OBJECT_ID, MAX_ORDER_ID_LENGTH, ORDER_ID_REGEX, DEFAULT_GRPC_URLS, DEFAULT_GRAPHQL_URLS } from './constants.js'
```

- [ ] **Step 4: Run typecheck**

Run: `cd packages/sdk && npx tsc --noEmit`
Expected: Errors in files that still import `rpcUrl` or `DEFAULT_RPC_URLS` — that's correct at this stage. Types + constants are ready.

- [ ] **Step 5: Commit**

```bash
git add packages/sdk/src/types.ts packages/sdk/src/constants.ts packages/sdk/src/index.ts
git commit -m "refactor(sdk): update config types and URL constants for gRPC migration"
```

---

## Task 2: Coin helper + validator + transaction type imports

**Files:**
- Modify: `packages/sdk/src/coins/helper.ts`
- Modify: `packages/sdk/src/coins/validator.ts`
- Modify: `packages/sdk/src/transactions/pay.ts:2`
- Modify: `packages/sdk/src/transactions/subscribe.ts:2`
- Modify: `packages/sdk/src/transactions/subscription.ts:2`

- [ ] **Step 1: Update `coins/helper.ts`**

Two changes: import type + `getCoins` → `listCoins` with new response shape.

```ts
import { Transaction } from '@mysten/sui/transactions'
import type { SuiGrpcClient } from '@mysten/sui/grpc'

/**
 * Get coins of a specific type owned by `owner`, merge them if needed,
 * and split exact `amount`. Returns the split coin argument for PTB use.
 *
 * Handles:
 * - Single coin with exact amount → use directly
 * - Single coin with excess → split
 * - Multiple coins → merge then split
 * - SUI → use tx.gas as source (no listCoins needed)
 */
export async function prepareCoin(
  tx: Transaction,
  client: SuiGrpcClient,
  owner: string,
  coinType: string,
  amount: bigint,
): Promise<ReturnType<Transaction['splitCoins']>> {
  const isSUI = coinType === '0x2::sui::SUI'

  if (isSUI) {
    // For SUI, split from gas coin
    return tx.splitCoins(tx.gas, [amount])
  }

  // Fetch all coins of this type
  const { objects: coins } = await client.listCoins({
    owner,
    coinType,
  })

  if (!coins || coins.length === 0) {
    throw new Error(`No ${coinType} coins found for ${owner}`)
  }

  // Sort by balance descending — use largest coins first
  coins.sort((a, b) => Number(BigInt(b.balance) - BigInt(a.balance)))

  // Check total balance
  const totalBalance = coins.reduce((sum, c) => sum + BigInt(c.balance), 0n)
  if (totalBalance < amount) {
    throw new Error(
      `Insufficient ${coinType} balance: have ${totalBalance}, need ${amount}`
    )
  }

  if (coins.length === 1) {
    // Single coin — split from it
    const coinRef = tx.object(coins[0].objectId)
    return tx.splitCoins(coinRef, [amount])
  }

  // Multiple coins — merge into first, then split
  const primary = tx.object(coins[0].objectId)
  const rest = coins.slice(1).map(c => tx.object(c.objectId))
  tx.mergeCoins(primary, rest)
  return tx.splitCoins(primary, [amount])
}
```

Note: `coins[0].coinObjectId` → `coins[0].objectId` — gRPC `Coin` type uses `objectId` not `coinObjectId`.

- [ ] **Step 2: Update `coins/validator.ts`**

```ts
import type { SuiGrpcClient } from '@mysten/sui/grpc'

/**
 * Validate that a coin type exists on-chain by checking CoinMetadata.
 * Returns decimals if found, throws if not.
 */
export async function validateCoinType(
  client: SuiGrpcClient,
  coinType: string,
): Promise<number> {
  const { coinMetadata } = await client.getCoinMetadata({ coinType })
  if (!coinMetadata) {
    throw new Error(`Coin type not found on-chain: ${coinType}`)
  }
  return coinMetadata.decimals
}
```

Note: gRPC `getCoinMetadata` returns `{ coinMetadata: { decimals, ... } }` wrapper — need to destructure.

- [ ] **Step 3: Update transaction file type imports**

For each of these 3 files, replace the import line:

`packages/sdk/src/transactions/pay.ts` line 2:
```ts
// Before
import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'
// After
import type { SuiGrpcClient } from '@mysten/sui/grpc'
```

Then replace all `SuiJsonRpcClient` parameter types with `SuiGrpcClient` in the function signatures:
- `pay.ts`: `buildPayOnceV2(client: SuiGrpcClient, ...)` and `buildPayOnce(client: SuiGrpcClient, ...)`
- `subscribe.ts`: `buildSubscribeV2(client: SuiGrpcClient, ...)` and `buildSubscribe(client: SuiGrpcClient, ...)`
- `subscription.ts`: `buildFundSubscription(client: SuiGrpcClient, ...)`

- [ ] **Step 4: Run typecheck**

Run: `cd packages/sdk && npx tsc --noEmit`
Expected: Errors only in `client.ts`, `version.ts`, `events/stream.ts` (not yet migrated). All modified files should be clean.

- [ ] **Step 5: Commit**

```bash
git add packages/sdk/src/coins/ packages/sdk/src/transactions/
git commit -m "refactor(sdk): migrate coin/transaction modules to SuiGrpcClient"
```

---

## Task 3: Version detection

**Files:**
- Modify: `packages/sdk/src/version.ts`

- [ ] **Step 1: Rewrite version.ts**

Replace `getNormalizedMoveModule` with `getMoveFunction` try/catch:

```ts
// packages/sdk/src/version.ts

import type { SuiGrpcClient } from '@mysten/sui/grpc'

export interface VersionInfo {
  hasV2: boolean
}

const cache = new WeakMap<SuiGrpcClient, VersionInfo>()

export async function detectVersion(client: SuiGrpcClient, packageId: string): Promise<VersionInfo> {
  const cached = cache.get(client)
  if (cached) return cached

  try {
    await client.getMoveFunction({
      packageId,
      moduleName: 'payment',
      name: 'pay_once_v2',
    })
    const result: VersionInfo = { hasV2: true }
    cache.set(client, result)
    return result
  } catch {
    const result: VersionInfo = { hasV2: false }
    cache.set(client, result)
    return result
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add packages/sdk/src/version.ts
git commit -m "refactor(sdk): version detection via getMoveFunction (gRPC)"
```

---

## Task 4: GraphQL event queries + EventStream

**Files:**
- Create: `packages/sdk/src/events/queries.ts`
- Modify: `packages/sdk/src/events/stream.ts`
- Modify: `packages/sdk/src/events/index.ts` (if exists, add queries export)

- [ ] **Step 1: Create `events/queries.ts`**

```ts
// packages/sdk/src/events/queries.ts

/**
 * GraphQL query for paginated event listing.
 * Used by EventStream (polling) and getPaymentHistory.
 */
export const QUERY_EVENTS = `
  query QueryEvents(
    $type: String!
    $after: String
    $first: Int
  ) {
    events(
      filter: { type: $type }
      after: $after
      first: $first
    ) {
      nodes {
        contents { json }
        sender { address }
        type { repr }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
`

/** Response type for QUERY_EVENTS */
export interface QueryEventsResult {
  events: {
    nodes: Array<{
      contents: { json: Record<string, unknown> } | null
      sender: { address: string } | null
      type: { repr: string } | null
    }>
    pageInfo: {
      hasNextPage: boolean
      endCursor: string | null
    }
  }
}
```

- [ ] **Step 2: Rewrite `events/stream.ts`**

```ts
// packages/sdk/src/events/stream.ts

import type { SuiGraphQLClient } from '@mysten/sui/graphql'
import type { EventCallback, FloatSyncEventData, FloatSyncEventName, Unsubscribe } from '../types.js'
import { normalizeEvent } from './types.js'
import { QUERY_EVENTS } from './queries.js'
import type { QueryEventsResult } from './queries.js'

interface ListenerEntry {
  callback: EventCallback
  filter?: Record<string, unknown>
}

const DEFAULT_POLL_INTERVAL_MS = 3000

export class EventStream {
  private packageId: string
  private listeners: Map<string, Set<ListenerEntry>> = new Map()
  private pollTimer?: ReturnType<typeof setInterval>
  private cursor?: string | null

  constructor(packageId: string) {
    this.packageId = packageId
  }

  on(
    event: FloatSyncEventName,
    callback: EventCallback,
    filter?: Record<string, unknown>,
  ): Unsubscribe {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set())
    }

    const entry: ListenerEntry = { callback, filter }
    this.listeners.get(event)!.add(entry)

    return () => {
      this.listeners.get(event)?.delete(entry)
    }
  }

  /**
   * Start polling for on-chain events via GraphQL.
   * Uses cursor tracking to only receive new events.
   */
  async start(client: SuiGraphQLClient, intervalMs = DEFAULT_POLL_INTERVAL_MS): Promise<void> {
    // Seed cursor from latest event so we only see new events
    const eventType = `${this.packageId}::events`
    const seed = await client.query<QueryEventsResult>({
      query: QUERY_EVENTS,
      variables: { type: eventType, first: 1 },
    })
    if (seed.data?.events.nodes.length) {
      this.cursor = seed.data.events.pageInfo.endCursor
    }

    this.pollTimer = setInterval(async () => {
      try {
        const result = await client.query<QueryEventsResult>({
          query: QUERY_EVENTS,
          variables: {
            type: eventType,
            after: this.cursor ?? undefined,
            first: 50,
          },
        })

        if (!result.data) return

        for (const node of result.data.events.nodes) {
          if (!node.type?.repr || !node.contents?.json) continue
          const data = normalizeEvent(node.type.repr, node.contents.json)
          this.dispatch(data)
        }

        if (result.data.events.pageInfo.endCursor) {
          this.cursor = result.data.events.pageInfo.endCursor
        }
      } catch {
        // Silently skip poll errors — next interval will retry
      }
    }, intervalMs)
  }

  stop(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = undefined
    }
  }

  /** Dispatch an event to matching listeners. Exposed for testing. */
  dispatch(event: FloatSyncEventData): void {
    const dispatch = (entries: Set<ListenerEntry> | undefined) => {
      if (!entries) return
      for (const entry of entries) {
        if (entry.filter && !this.matchesFilter(event, entry.filter)) continue
        entry.callback(event)
      }
    }

    // Exact event name listeners
    dispatch(this.listeners.get(event.type))
    // Wildcard listeners
    dispatch(this.listeners.get('*'))
  }

  private matchesFilter(event: FloatSyncEventData, filter: Record<string, unknown>): boolean {
    for (const [key, value] of Object.entries(filter)) {
      if (event[key] !== value) return false
    }
    return true
  }
}
```

- [ ] **Step 3: Update `events/index.ts` if needed**

Check if `events/index.ts` exists and add export for `queries.ts`:

```ts
export { QUERY_EVENTS } from './queries.js'
export type { QueryEventsResult } from './queries.js'
```

- [ ] **Step 4: Commit**

```bash
git add packages/sdk/src/events/
git commit -m "refactor(sdk): event stream + queries via GraphQL"
```

---

## Task 5: Client class migration

**Files:**
- Modify: `packages/sdk/src/client.ts`

This is the main integration point. All sub-modules are already migrated.

- [ ] **Step 1: Rewrite client.ts**

```ts
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
import { QUERY_EVENTS } from './events/queries.js'
import type { QueryEventsResult } from './events/queries.js'

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

  // ── Raw Client Access ──

  /** Access the underlying SuiGrpcClient for advanced usage. */
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

  async pay(params: PayParams, sender: string): Promise<TransactionResult> {
    const key = IdempotencyGuard.key(this.config.merchantId, params.orderId)
    const existing = this.idempotency.check(key)
    if (existing === 'pending') {
      throw new ValidationError('DUPLICATE_PENDING', `Payment for order "${params.orderId}" is already in progress`)
    }
    if (existing) {
      return { tx: (await buildPayOnceV2(this.grpcClient, this.config, params, sender)) }
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

  processSubscription(subscriptionId: ObjectId, coinType: string): TransactionResult {
    return { tx: buildProcessSubscription(this.config, subscriptionId, coinType) }
  }

  cancelSubscription(subscriptionId: ObjectId, coinType: string): TransactionResult {
    return { tx: buildCancelSubscription(this.config, subscriptionId, coinType) }
  }

  async fundSubscription(params: FundParams, sender: string): Promise<TransactionResult> {
    const tx = await buildFundSubscription(this.grpcClient, this.config, params, sender)
    return { tx }
  }

  registerMerchant(params: RegisterParams): TransactionResult {
    return { tx: buildRegisterMerchant(this.config, params) }
  }

  claimYield(merchantCapId: string): TransactionResult {
    return { tx: buildClaimYield(this.config, merchantCapId) }
  }

  selfPause(merchantCapId: string): TransactionResult {
    return { tx: buildSelfPause(this.config, merchantCapId) }
  }

  selfUnpause(merchantCapId: string): TransactionResult {
    return { tx: buildSelfUnpause(this.config, merchantCapId) }
  }

  // ── Idempotency ──

  get idempotencyGuard(): IdempotencyGuard {
    return this.idempotency
  }

  // ── Events ──

  on(event: FloatSyncEventName, callback: EventCallback, filter?: Record<string, unknown>): Unsubscribe {
    return this.events.on(event, callback, filter)
  }

  async startEventStream(): Promise<void> {
    await this.events.start(this.graphqlClient)
  }

  stopEventStream(): void {
    this.events.stop()
  }

  // ── Query Methods ──

  async getMerchant(merchantId?: ObjectId): Promise<MerchantInfo> {
    const id = merchantId ?? this.config.merchantId
    const { object } = await this.grpcClient.getObject({
      objectId: id,
      include: { json: true },
    })

    if (!object?.json) {
      throw new ValidationError('MERCHANT_NOT_FOUND', `Merchant ${id} not found`)
    }

    const fields = object.json as Record<string, unknown>
    return deserializeMerchant(id, fields)
  }

  async getSubscription(subscriptionId: ObjectId): Promise<SubscriptionInfo> {
    const { object } = await this.grpcClient.getObject({
      objectId: subscriptionId,
      include: { json: true },
    })

    if (!object?.json) {
      throw new ValidationError('SUBSCRIPTION_NOT_FOUND', `Subscription ${subscriptionId} not found`)
    }

    const fields = object.json as Record<string, unknown>
    return deserializeSubscription(subscriptionId, fields)
  }

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

    // Client-side payer filter
    if (payer) {
      events = events.filter((e) => e.payer === payer)
    }

    // Client-side reverse for desc order (GraphQL returns ascending by default)
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
```

- [ ] **Step 2: Run typecheck**

Run: `cd packages/sdk && npx tsc --noEmit`
Expected: PASS (all source files now use gRPC/GraphQL types)

- [ ] **Step 3: Commit**

```bash
git add packages/sdk/src/client.ts
git commit -m "refactor(sdk): client class migration to gRPC + GraphQL"
```

---

## Task 6: Test mock migration

**Files:**
- Modify: `packages/sdk/test/client.test.ts`
- Modify: `packages/sdk/test/integration.test.ts`
- Modify: `packages/sdk/test/monkey.test.ts`

All three test files mock `@mysten/sui/jsonRpc`. They need to mock `@mysten/sui/grpc` + `@mysten/sui/graphql` instead. The mock shape changes:
- `getCoins` → `listCoins` (response: `{ objects: [...] }` not `{ data: [...] }`)
- `getNormalizedMoveModule` → `getMoveFunction` (success = resolved, not-found = throws)
- `getObject` → response: `{ object: { json: {...} } }` not `{ data: { content: { fields: {...} } } }`
- `queryEvents` → removed from gRPC mock, handled by GraphQL mock
- Constructor: `{ baseUrl, network }` not `{ url, network }`

- [ ] **Step 1: Create shared mock helper**

Create `packages/sdk/test/_mocks.ts` to DRY the mock setup:

```ts
// packages/sdk/test/_mocks.ts
import { vi } from 'vitest'

export const mockGetObject = vi.fn()
export const mockListCoins = vi.fn()
export const mockGetMoveFunction = vi.fn()
export const mockGetCoinMetadata = vi.fn()
export const mockGraphQLQuery = vi.fn()

export function setupGrpcMock() {
  vi.mock('@mysten/sui/grpc', () => {
    class MockSuiGrpcClient {
      baseUrl: string
      network: string
      constructor(opts: { baseUrl: string; network: string }) {
        this.baseUrl = opts.baseUrl
        this.network = opts.network
      }
      getObject = mockGetObject
      listCoins = mockListCoins
      getMoveFunction = mockGetMoveFunction
      getCoinMetadata = mockGetCoinMetadata
    }
    return { SuiGrpcClient: MockSuiGrpcClient }
  })
}

export function setupGraphQLMock() {
  vi.mock('@mysten/sui/graphql', () => {
    class MockSuiGraphQLClient {
      url: string
      network: string
      constructor(opts: { url: string; network: string }) {
        this.url = opts.url
        this.network = opts.network
      }
      query = mockGraphQLQuery
    }
    return { SuiGraphQLClient: MockSuiGraphQLClient }
  })
}

/** Setup v2 version detection mock (getMoveFunction succeeds) */
export function mockV2Available() {
  mockGetMoveFunction.mockResolvedValue({
    function: { packageId: '0x', moduleName: 'payment', name: 'pay_once_v2' },
  })
}

/** Setup v1-only version detection mock (getMoveFunction throws) */
export function mockV1Only() {
  mockGetMoveFunction.mockRejectedValue(new Error('Function not found'))
}

/** Setup default coin mock for SUI-based tests */
export function mockDefaultCoins() {
  mockListCoins.mockResolvedValue({
    objects: [{ objectId: '0xcoin1', balance: '999999999999', version: '1', digest: 'abc', owner: { AddressOwner: '0x' }, type: '0x2::coin::Coin<0x2::sui::SUI>' }],
    hasNextPage: false,
    cursor: null,
  })
}
```

- [ ] **Step 2: Migrate `client.test.ts`**

Replace the `vi.mock('@mysten/sui/jsonRpc', ...)` block and update all tests:

Key changes:
- Replace mock import block with:
  ```ts
  import { mockGetObject, mockListCoins, mockGetMoveFunction, mockGraphQLQuery, mockDefaultCoins, mockV2Available } from './_mocks.js'
  import { setupGrpcMock, setupGraphQLMock } from './_mocks.js'
  setupGrpcMock()
  setupGraphQLMock()
  ```
- `client.suiClient` → `client.rawClient`
- `mockGetNormalizedMoveModule.mockResolvedValue(...)` → `mockV2Available()` or `mockGetMoveFunction.mockResolvedValue(...)`
- `mockGetCoins` → `mockListCoins` with `{ objects: [...] }` response shape
- `mockGetObject` response: `{ object: { json: { owner: '0x...', ... } } }` instead of `{ data: { content: { dataType: 'moveObject', fields: { ... } } } }`
- `mockQueryEvents` → `mockGraphQLQuery` with GraphQL response shape:
  ```ts
  mockGraphQLQuery.mockResolvedValue({
    data: {
      events: {
        nodes: [{ type: { repr: '0xpkg::events::PaymentReceivedV2' }, contents: { json: { merchant_id: '0x...', amount: '100' } }, sender: { address: '0x...' } }],
        pageInfo: { hasNextPage: false, endCursor: null },
      },
    },
  })
  ```
- Remove test for `rpcUrl` config → replace with tests for `grpcUrl` and `graphqlUrl`

- [ ] **Step 3: Migrate `integration.test.ts`**

Same mock replacement pattern as client.test.ts. Key differences:
- `setupV2Mocks()` helper → use `mockV2Available()` + `mockDefaultCoins()`
- Event stream tests → use `mockGraphQLQuery`
- Payment history tests → `mockGraphQLQuery` response shape

- [ ] **Step 4: Migrate `monkey.test.ts`**

Same mock replacement. This file primarily tests edge cases on orderId, amounts, and config validation — the mock migration is mechanical.

- [ ] **Step 5: Run all tests**

Run: `cd packages/sdk && pnpm test`
Expected: 153/153 PASS

- [ ] **Step 6: Commit**

```bash
git add packages/sdk/test/
git commit -m "test(sdk): migrate all test mocks from JSON-RPC to gRPC + GraphQL"
```

---

## Task 7: Build verification + React typecheck

**Files:**
- Verify: `packages/sdk/` (build)
- Verify: `packages/react/` (typecheck + tests)
- Verify: `apps/demo/` (build)

- [ ] **Step 1: SDK build**

Run: `cd packages/sdk && pnpm build`
Expected: BUILD SUCCESS

- [ ] **Step 2: SDK typecheck**

Run: `cd packages/sdk && npx tsc --noEmit`
Expected: PASS

- [ ] **Step 3: React package typecheck + tests**

The React package imports `FloatSync` and `FloatSyncConfig` from `@floatsync/sdk`. Since `FloatSyncConfig.rpcUrl` was removed, check if any React code references it.

Run: `cd packages/react && npx tsc --noEmit && pnpm test`
Expected: PASS (React provider only passes config through, doesn't reference `rpcUrl`)

- [ ] **Step 4: Demo app build**

Run: `cd apps/demo && pnpm build`
Expected: PASS (demo config doesn't use `rpcUrl`)

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "build: verify SDK + React + Demo build after gRPC migration"
```

---

## Task 8: Cleanup + documentation

**Files:**
- Modify: `packages/sdk/src/index.ts` (verify no stale jsonRpc re-exports)
- Modify: `tasks/progress.md`

- [ ] **Step 1: Grep for any remaining JSON-RPC references**

Run: `grep -r 'jsonRpc\|SuiJsonRpcClient\|getJsonRpcFullnodeUrl\|DEFAULT_RPC_URLS\|rpcUrl' packages/sdk/src/ packages/react/src/ apps/demo/`
Expected: Zero matches

- [ ] **Step 2: Grep for any remaining `getCoins` or `coinObjectId` references**

Run: `grep -r 'getCoins\b\|coinObjectId' packages/sdk/src/`
Expected: Zero matches

- [ ] **Step 3: Update progress.md**

Add gRPC migration entry to `tasks/progress.md`.

- [ ] **Step 4: Final commit**

```bash
git add tasks/progress.md
git commit -m "docs: update progress after gRPC migration"
```
