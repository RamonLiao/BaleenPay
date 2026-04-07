import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import {
  mockGetObject,
  mockListCoins,
  mockGetMoveFunction,
  mockGraphQLQuery,
  setupGrpcMock,
  setupGraphQLMock,
  mockV2Available,
  mockV1Only,
  mockDefaultCoins,
  makeGraphQLEventsResponse,
} from './_mocks.js'
import { BaleenPay } from '../src/client.js'
import { AdminClient } from '../src/admin.js'
import { IdempotencyGuard } from '../src/idempotency.js'
import { ValidationError } from '../src/errors.js'

// Hoist mocks before any imports that use them
setupGrpcMock()
setupGraphQLMock()

const PKG = '0xpkg_integration'
const MERCHANT = '0xmerchant_int'
const SENDER = '0xsender_addr'

const baseConfig = {
  network: 'testnet' as const,
  packageId: PKG,
  merchantId: MERCHANT,
  registryId: '0xregistry',
  routerConfigId: '0xrouter',
}

/** Setup mocks for a v2-capable contract */
function setupV2Mocks() {
  mockV2Available()
  mockDefaultCoins()
}

/** Setup mocks for a v1-only contract */
function setupV1Mocks() {
  mockV1Only()
  mockDefaultCoins()
}

beforeEach(() => {
  vi.clearAllMocks()
})

// ────────────────────────────────────────────────────────────
//  E2E Flow: Full merchant lifecycle
// ────────────────────────────────────────────────────────────

describe('Integration: Full merchant lifecycle (V2)', () => {
  let client: BaleenPay

  beforeEach(() => {
    setupV2Mocks()
    client = new BaleenPay(baseConfig)
  })

  it('register → pay → idempotency block → subscribe → query merchant → events', async () => {
    // ── Step 1: Register merchant ──
    const regResult = client.registerMerchant({ brandName: 'IntegrationShop' })
    expect(regResult.tx).toBeDefined()

    // ── Step 2: Pay with orderId ──
    const payResult = await client.pay(
      { amount: 1_000_000n, coin: 'SUI', orderId: 'order-int-001' },
      SENDER,
    )
    expect(payResult.tx).toBeDefined()

    // Version detection should have been called
    expect(mockGetMoveFunction).toHaveBeenCalledWith({
      packageId: PKG,
      moduleName: 'payment',
      name: 'pay_once_v2',
    })

    // ── Step 3: Same orderId → idempotency guard marks pending ──
    await expect(
      client.pay({ amount: 1_000_000n, coin: 'SUI', orderId: 'order-int-001' }, SENDER),
    ).rejects.toThrow('already in progress')

    // ── Step 4: Subscribe ──
    const subResult = await client.subscribe(
      {
        amountPerPeriod: 100_000n,
        periodMs: 86_400_000,
        prepaidPeriods: 3,
        coin: 'SUI',
        orderId: 'sub-int-001',
      },
      SENDER,
    )
    expect(subResult.tx).toBeDefined()

    // ── Step 5: Query merchant ──
    mockGetObject.mockResolvedValue({
      object: {
        json: {
          owner: '0xowner',
          brand_name: 'IntegrationShop',
          total_received: '1000000',
          idle_principal: '800000',
          accrued_yield: '10000',
          active_subscriptions: 1,
          paused_by_admin: false,
          paused_by_self: false,
        },
      },
    })

    const merchant = await client.getMerchant()
    expect(merchant.brandName).toBe('IntegrationShop')
    expect(merchant.totalReceived).toBe(1_000_000n)
    expect(merchant.activeSubscriptions).toBe(1)

    // ── Step 6: Event subscription ──
    const received: unknown[] = []
    const unsub = client.on('payment.received', (e) => received.push(e))
    expect(typeof unsub).toBe('function')
    unsub()
  })

  it('pay → markCompleted → second pay rebuilds tx (completed idempotency)', async () => {
    const params = { amount: 500_000n, coin: 'SUI', orderId: 'order-comp-001' }
    await client.pay(params, SENDER)

    // Mark the pending key as completed
    const key = IdempotencyGuard.key(MERCHANT, 'order-comp-001')
    client.idempotencyGuard.markCompleted(key, {
      digest: '0xdigest',
      status: 'success',
      events: [],
      gasUsed: 1000n,
    })

    // Second call with same orderId — idempotency returns 'completed', but still builds tx
    const result2 = await client.pay(params, SENDER)
    expect(result2.tx).toBeDefined()
  })
})

// ────────────────────────────────────────────────────────────
//  V1 fallback: Version detection routes to legacy functions
// ────────────────────────────────────────────────────────────

describe('Integration: V1 fallback path', () => {
  let client: BaleenPay

  beforeEach(() => {
    setupV1Mocks()
    client = new BaleenPay(baseConfig)
  })

  it('pay routes to pay_once (v1) when v2 not available', async () => {
    const result = await client.pay(
      { amount: 1_000_000n, coin: 'SUI', orderId: 'v1-order-001' },
      SENDER,
    )
    expect(result.tx).toBeDefined()
    // Version detection called once
    expect(mockGetMoveFunction).toHaveBeenCalledTimes(1)
  })

  it('subscribe routes to subscribe (v1) when v2 not available', async () => {
    const result = await client.subscribe(
      {
        amountPerPeriod: 50_000n,
        periodMs: 3_600_000,
        prepaidPeriods: 5,
        coin: 'SUI',
        orderId: 'v1-sub-001',
      },
      SENDER,
    )
    expect(result.tx).toBeDefined()
  })

  it('version is cached — second call does not re-fetch', async () => {
    await client.pay({ amount: 100n, coin: 'SUI', orderId: 'cache-001' }, SENDER)
    await client.subscribe(
      { amountPerPeriod: 100n, periodMs: 1000, prepaidPeriods: 1, coin: 'SUI', orderId: 'cache-002' },
      SENDER,
    )
    // getMoveFunction called only once despite two operations
    expect(mockGetMoveFunction).toHaveBeenCalledTimes(1)
  })
})

// ────────────────────────────────────────────────────────────
//  Coin helper integration: non-SUI coins require listCoins
// ────────────────────────────────────────────────────────────

describe('Integration: Coin helper with USDC', () => {
  let client: BaleenPay

  beforeEach(() => {
    setupV2Mocks()
    client = new BaleenPay(baseConfig)
  })

  it('pay with USDC fetches coins and builds PTB', async () => {
    mockListCoins.mockResolvedValue({
      objects: [
        { objectId: '0xusdc1', balance: '5000000' },
        { objectId: '0xusdc2', balance: '3000000' },
      ],
    })

    const result = await client.pay(
      { amount: 2_000_000n, coin: 'USDC', orderId: 'usdc-001' },
      SENDER,
    )
    expect(result.tx).toBeDefined()

    // listCoins should have been called for USDC
    expect(mockListCoins).toHaveBeenCalledWith({
      owner: SENDER,
      coinType: expect.stringContaining('::usdc::USDC'),
    })
  })

  it('pay with USDC fails when insufficient balance', async () => {
    mockListCoins.mockResolvedValue({
      objects: [{ objectId: '0xusdc1', balance: '100' }],
    })

    await expect(
      client.pay({ amount: 2_000_000n, coin: 'USDC', orderId: 'usdc-fail-001' }, SENDER),
    ).rejects.toThrow('Insufficient')

    // Idempotency key should be cleaned up on error
    expect(client.idempotencyGuard.size).toBe(0)
  })

  it('pay with USDC fails when no coins found', async () => {
    mockListCoins.mockResolvedValue({ objects: [] })

    await expect(
      client.pay({ amount: 1_000_000n, coin: 'USDC', orderId: 'usdc-empty-001' }, SENDER),
    ).rejects.toThrow('No')

    expect(client.idempotencyGuard.size).toBe(0)
  })
})

// ────────────────────────────────────────────────────────────
//  Subscription lifecycle
// ────────────────────────────────────────────────────────────

describe('Integration: Subscription operations', () => {
  let client: BaleenPay

  beforeEach(() => {
    setupV2Mocks()
    client = new BaleenPay(baseConfig)
  })

  it('subscribe → process → fund → cancel', async () => {
    // Subscribe
    const sub = await client.subscribe(
      {
        amountPerPeriod: 100_000n,
        periodMs: 86_400_000,
        prepaidPeriods: 3,
        coin: 'SUI',
        orderId: 'sub-lifecycle-001',
      },
      SENDER,
    )
    expect(sub.tx).toBeDefined()

    // Process subscription (anyone can call)
    const process = client.processSubscription('0xsubId', '0x2::sui::SUI')
    expect(process.tx).toBeDefined()

    // Fund subscription
    const fund = await client.fundSubscription(
      { subscriptionId: '0xsubId', amount: 200_000n, coin: 'SUI' },
      SENDER,
    )
    expect(fund.tx).toBeDefined()

    // Cancel subscription
    const cancel = client.cancelSubscription('0xsubId', '0x2::sui::SUI')
    expect(cancel.tx).toBeDefined()
  })

  it('getSubscription deserializes on-chain data', async () => {
    mockGetObject.mockResolvedValue({
      object: {
        json: {
          merchant_id: MERCHANT,
          payer: SENDER,
          amount_per_period: '100000',
          period_ms: 86400000,
          next_due: 1711324800000,
          balance: '300000',
        },
      },
    })

    const info = await client.getSubscription('0xsubId')
    expect(info.subscriptionId).toBe('0xsubId')
    expect(info.merchantId).toBe(MERCHANT)
    expect(info.payer).toBe(SENDER)
    expect(info.amountPerPeriod).toBe(100_000n)
    expect(info.balance).toBe(300_000n)
  })
})

// ────────────────────────────────────────────────────────────
//  Event stream integration
// ────────────────────────────────────────────────────────────

describe('Integration: Event stream (polling)', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('startEventStream seeds cursor and starts polling', async () => {
    // Seed query returns empty (no prior events)
    mockGraphQLQuery.mockResolvedValue(makeGraphQLEventsResponse([]))

    const client = new BaleenPay(baseConfig)
    await client.startEventStream()

    // Seed call should have been made with first: 1
    expect(mockGraphQLQuery).toHaveBeenCalledWith(
      expect.objectContaining({
        variables: expect.objectContaining({ first: 1 }),
      }),
    )

    client.stopEventStream()
  })

  it('poll delivers normalized events to listeners', async () => {
    // Seed: no prior events
    mockGraphQLQuery.mockResolvedValueOnce(makeGraphQLEventsResponse([]))

    const client = new BaleenPay(baseConfig)
    const events: unknown[] = []
    client.on('payment.received', (e) => events.push(e))

    await client.startEventStream()

    // Next poll returns an event
    mockGraphQLQuery.mockResolvedValueOnce(
      makeGraphQLEventsResponse([
        {
          type: `${PKG}::events::PaymentReceivedV2`,
          json: {
            merchant_id: MERCHANT,
            payer: SENDER,
            amount: '1000000',
            payment_type: 0,
            timestamp: 1711324800000,
            order_id: 'evt-001',
            coin_type: '0x2::sui::SUI',
          },
        },
      ]),
    )

    // Advance timer to trigger poll
    await vi.advanceTimersByTimeAsync(3000)

    expect(events).toHaveLength(1)
    expect((events[0] as Record<string, unknown>).orderId).toBe('evt-001')
    expect((events[0] as Record<string, unknown>).amount).toBe(1_000_000n)

    client.stopEventStream()
  })

  it('wildcard listener receives all event types', async () => {
    mockGraphQLQuery.mockResolvedValueOnce(makeGraphQLEventsResponse([]))

    const client = new BaleenPay(baseConfig)
    const events: unknown[] = []
    client.on('*', (e) => events.push(e))

    await client.startEventStream()

    mockGraphQLQuery.mockResolvedValueOnce(
      makeGraphQLEventsResponse([
        {
          type: `${PKG}::events::MerchantPaused`,
          json: { merchant_id: MERCHANT },
        },
        {
          type: `${PKG}::events::YieldClaimed`,
          json: { merchant_id: MERCHANT, amount: '50000' },
        },
      ]),
    )

    await vi.advanceTimersByTimeAsync(3000)

    expect(events).toHaveLength(2)

    client.stopEventStream()
  })

  it('filtered listener only receives matching events', async () => {
    mockGraphQLQuery.mockResolvedValueOnce(makeGraphQLEventsResponse([]))

    const client = new BaleenPay(baseConfig)
    const events: unknown[] = []
    client.on('payment.received', (e) => events.push(e), { payer: SENDER })

    await client.startEventStream()

    mockGraphQLQuery.mockResolvedValueOnce(
      makeGraphQLEventsResponse([
        {
          type: `${PKG}::events::PaymentReceivedV2`,
          json: { merchant_id: MERCHANT, payer: SENDER, amount: '100', order_id: 'x1', coin_type: 'SUI', timestamp: 1000, payment_type: 0 },
        },
        {
          type: `${PKG}::events::PaymentReceivedV2`,
          json: { merchant_id: MERCHANT, payer: '0xother', amount: '200', order_id: 'x2', coin_type: 'SUI', timestamp: 2000, payment_type: 0 },
        },
      ]),
    )

    await vi.advanceTimersByTimeAsync(3000)

    expect(events).toHaveLength(1)

    client.stopEventStream()
  })
})

// ────────────────────────────────────────────────────────────
//  Payment history with pagination
// ────────────────────────────────────────────────────────────

describe('Integration: Payment history', () => {
  let client: BaleenPay

  beforeEach(() => {
    client = new BaleenPay(baseConfig)
  })

  it('fetches page 1, then page 2 with cursor', async () => {
    // Page 1
    mockGraphQLQuery.mockResolvedValueOnce(
      makeGraphQLEventsResponse(
        [{
          type: `${PKG}::events::PaymentReceivedV2`,
          json: { merchant_id: MERCHANT, payer: SENDER, amount: '100', order_id: 'p1', coin_type: 'SUI', timestamp: 1000, payment_type: 0 },
        }],
        { hasNextPage: true, endCursor: 'cursor-page1' },
      ),
    )

    const page1 = await client.getPaymentHistory({ limit: 1 })
    expect(page1.events).toHaveLength(1)
    expect(page1.hasNextPage).toBe(true)
    expect(page1.nextCursor).toBeDefined()

    // Page 2
    mockGraphQLQuery.mockResolvedValueOnce(
      makeGraphQLEventsResponse(
        [{
          type: `${PKG}::events::PaymentReceivedV2`,
          json: { merchant_id: MERCHANT, payer: '0xother', amount: '200', order_id: 'p2', coin_type: 'SUI', timestamp: 2000, payment_type: 0 },
        }],
        { hasNextPage: false, endCursor: null },
      ),
    )

    const page2 = await client.getPaymentHistory({ limit: 1, cursor: page1.nextCursor })
    expect(page2.events).toHaveLength(1)
    expect(page2.events[0].orderId).toBe('p2')
    expect(page2.hasNextPage).toBe(false)
  })

  it('GraphQL query is called with correct variables', async () => {
    mockGraphQLQuery.mockResolvedValue(makeGraphQLEventsResponse([]))

    await client.getPaymentHistory({ order: 'asc' })

    // With GraphQL, order is handled client-side; verify query is called
    expect(mockGraphQLQuery).toHaveBeenCalledWith(
      expect.objectContaining({
        variables: expect.objectContaining({
          type: `${PKG}::events::PaymentReceivedV2`,
        }),
      }),
    )
  })
})

// ────────────────────────────────────────────────────────────
//  Admin operations integration
// ────────────────────────────────────────────────────────────

describe('Integration: AdminClient', () => {
  it('pause → unpause → setRouterMode', () => {
    const admin = new AdminClient(baseConfig)

    const pause = admin.pause('0xadminCap')
    expect(pause.tx).toBeDefined()

    const unpause = admin.unpause('0xadminCap')
    expect(unpause.tx).toBeDefined()

    const setMode = admin.setRouterMode('0xadminCap', '0xrouter', 1)
    expect(setMode.tx).toBeDefined()
  })
})

// ────────────────────────────────────────────────────────────
//  Self-pause integration (MerchantCap ops)
// ────────────────────────────────────────────────────────────

describe('Integration: Self-pause / unpause', () => {
  it('selfPause and selfUnpause build valid PTBs', () => {
    const client = new BaleenPay(baseConfig)

    const pause = client.selfPause('0xcap')
    expect(pause.tx).toBeDefined()

    const unpause = client.selfUnpause('0xcap')
    expect(unpause.tx).toBeDefined()
  })
})

// ────────────────────────────────────────────────────────────
//  Idempotency guard: error cleanup
// ────────────────────────────────────────────────────────────

describe('Integration: Idempotency error cleanup', () => {
  it('removes pending key when pay throws (e.g. insufficient coins)', async () => {
    setupV2Mocks()
    mockListCoins.mockResolvedValue({ objects: [] }) // no USDC coins

    const client = new BaleenPay(baseConfig)

    await expect(
      client.pay({ amount: 1_000_000n, coin: 'USDC', orderId: 'idem-err-001' }, SENDER),
    ).rejects.toThrow()

    // Pending key should have been cleaned up
    expect(client.idempotencyGuard.size).toBe(0)

    // Subsequent pay with same orderId should work (not blocked by stale pending)
    mockListCoins.mockResolvedValue({
      objects: [{ objectId: '0xusdc1', balance: '5000000' }],
    })
    const result = await client.pay(
      { amount: 1_000_000n, coin: 'USDC', orderId: 'idem-err-001' },
      SENDER,
    )
    expect(result.tx).toBeDefined()
  })

  it('removes pending key when subscribe throws', async () => {
    setupV2Mocks()
    mockListCoins.mockResolvedValue({ objects: [] }) // no USDC coins

    const client = new BaleenPay(baseConfig)

    await expect(
      client.subscribe(
        { amountPerPeriod: 100_000n, periodMs: 86_400_000, prepaidPeriods: 3, coin: 'USDC', orderId: 'sub-err-001' },
        SENDER,
      ),
    ).rejects.toThrow()

    expect(client.idempotencyGuard.size).toBe(0)
  })
})
