import { describe, it, expect, vi, beforeEach } from 'vitest'
import { FloatSync } from '../src/client.js'
import { ValidationError } from '../src/errors.js'

// ── Shared mocks ──

const mockGetCoins = vi.fn()
const mockGetNormalizedMoveModule = vi.fn()

vi.mock('@mysten/sui/jsonRpc', () => {
  class MockSuiJsonRpcClient {
    url: string
    constructor(opts: { url: string; network?: string }) {
      this.url = opts.url
    }
    getObject = vi.fn()
    queryEvents = vi.fn()
    getCoins = mockGetCoins
    getNormalizedMoveModule = mockGetNormalizedMoveModule
  }
  return {
    SuiJsonRpcClient: MockSuiJsonRpcClient,
    getJsonRpcFullnodeUrl: (network: string) => `https://fullnode.${network}.sui.io:443`,
  }
})

const SENDER = '0xsender'
const baseConfig = {
  network: 'testnet' as const,
  packageId: '0xpkg_monkey',
  merchantId: '0xmerchant_monkey',
}

beforeEach(() => {
  vi.clearAllMocks()
  // Default: v2 available
  mockGetNormalizedMoveModule.mockResolvedValue({
    exposedFunctions: { pay_once: {}, pay_once_v2: {}, subscribe: {}, subscribe_v2: {} },
  })
  mockGetCoins.mockResolvedValue({
    data: [{ coinObjectId: '0xcoin1', balance: '999999999999' }],
  })
})

// ────────────────────────────────────────────────────────────
//  Invalid config
// ────────────────────────────────────────────────────────────

describe('Monkey: Invalid config', () => {
  it('throws on empty packageId', () => {
    expect(() => new FloatSync({ ...baseConfig, packageId: '' })).toThrow(ValidationError)
  })

  it('throws on empty merchantId', () => {
    expect(() => new FloatSync({ ...baseConfig, merchantId: '' })).toThrow(ValidationError)
  })

  it('throws on missing network', () => {
    expect(() => new FloatSync({ ...baseConfig, network: '' as 'testnet' })).toThrow(ValidationError)
  })

  it('throws on undefined packageId', () => {
    expect(() => new FloatSync({ ...baseConfig, packageId: undefined as unknown as string })).toThrow()
  })

  it('throws on undefined merchantId', () => {
    expect(() => new FloatSync({ ...baseConfig, merchantId: undefined as unknown as string })).toThrow()
  })
})

// ────────────────────────────────────────────────────────────
//  Invalid orderId
// ────────────────────────────────────────────────────────────

describe('Monkey: Invalid orderId', () => {
  let client: FloatSync

  beforeEach(() => {
    client = new FloatSync(baseConfig)
  })

  it('rejects empty orderId', async () => {
    // Empty orderId fails at IdempotencyGuard.key (no orderId + no fallback)
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: '' }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects orderId with spaces', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: 'has space' }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects orderId with unicode (emoji)', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: 'order-🎉' }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects orderId with unicode (CJK)', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: '訂單-001' }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects orderId with null byte', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: 'order\x00id' }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects orderId with newline', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: 'order\nid' }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects orderId with tab', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: 'order\tid' }, SENDER),
    ).rejects.toThrow()
  })

  it('accepts 64-char orderId (max valid)', async () => {
    const id = 'a'.repeat(64)
    const result = await client.pay({ amount: 1000n, coin: 'SUI', orderId: id }, SENDER)
    expect(result.tx).toBeDefined()
  })

  it('rejects 65-char orderId (over max)', async () => {
    const id = 'a'.repeat(65)
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: id }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects email-like orderId (PII)', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: 'user@example.com' }, SENDER),
    ).rejects.toThrow(/PII/)
  })

  it('rejects phone-like orderId (PII)', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'SUI', orderId: '+886912345678' }, SENDER),
    ).rejects.toThrow(/PII/)
  })

  it('accepts orderId with special ASCII chars', async () => {
    const result = await client.pay(
      { amount: 1000n, coin: 'SUI', orderId: 'order-!@#$%^&*()_+' },
      SENDER,
    )
    expect(result.tx).toBeDefined()
  })

  it('accepts orderId with only printable punctuation', async () => {
    const result = await client.pay(
      { amount: 1000n, coin: 'SUI', orderId: '---' },
      SENDER,
    )
    expect(result.tx).toBeDefined()
  })
})

// ────────────────────────────────────────────────────────────
//  Invalid amounts
// ────────────────────────────────────────────────────────────

describe('Monkey: Invalid amounts', () => {
  let client: FloatSync

  beforeEach(() => {
    client = new FloatSync(baseConfig)
  })

  it('rejects amount = 0', async () => {
    await expect(
      client.pay({ amount: 0n, coin: 'SUI', orderId: 'zero-amt' }, SENDER),
    ).rejects.toThrow(/zero|greater/)
  })

  it('rejects negative amount', async () => {
    await expect(
      client.pay({ amount: -1n, coin: 'SUI', orderId: 'neg-amt' }, SENDER),
    ).rejects.toThrow()
  })

  it('accepts very large amount (u64 max)', async () => {
    // This should build the tx, even though the chain would reject insufficient coins
    // We mock sufficient coins
    mockGetCoins.mockResolvedValue({
      data: [{ coinObjectId: '0xwhale', balance: '18446744073709551615' }],
    })

    // For SUI (gas coin shortcut), amount validation happens at tx level
    const result = await client.pay(
      { amount: 18446744073709551615n, coin: 'SUI', orderId: 'max-u64' },
      SENDER,
    )
    expect(result.tx).toBeDefined()
  })
})

// ────────────────────────────────────────────────────────────
//  Invalid subscription params
// ────────────────────────────────────────────────────────────

describe('Monkey: Invalid subscription params', () => {
  let client: FloatSync

  beforeEach(() => {
    client = new FloatSync(baseConfig)
  })

  const validSub = {
    amountPerPeriod: 100_000n,
    periodMs: 86_400_000,
    prepaidPeriods: 3,
    coin: 'SUI' as const,
    orderId: 'sub-monkey',
  }

  it('rejects periodMs = 0', async () => {
    await expect(
      client.subscribe({ ...validSub, periodMs: 0, orderId: 'sub-m-1' }, SENDER),
    ).rejects.toThrow(/zero|greater/)
  })

  it('rejects negative periodMs', async () => {
    await expect(
      client.subscribe({ ...validSub, periodMs: -1000, orderId: 'sub-m-2' }, SENDER),
    ).rejects.toThrow(/zero|greater/)
  })

  it('rejects prepaidPeriods = 0', async () => {
    await expect(
      client.subscribe({ ...validSub, prepaidPeriods: 0, orderId: 'sub-m-3' }, SENDER),
    ).rejects.toThrow(/zero|greater/)
  })

  it('rejects prepaidPeriods > 1000', async () => {
    await expect(
      client.subscribe({ ...validSub, prepaidPeriods: 1001, orderId: 'sub-m-4' }, SENDER),
    ).rejects.toThrow(/exceed|maximum|1000/)
  })

  it('accepts prepaidPeriods = 1000 (boundary)', async () => {
    const result = await client.subscribe(
      { ...validSub, prepaidPeriods: 1000, orderId: 'sub-m-5' },
      SENDER,
    )
    expect(result.tx).toBeDefined()
  })

  it('rejects amountPerPeriod = 0', async () => {
    await expect(
      client.subscribe({ ...validSub, amountPerPeriod: 0n, orderId: 'sub-m-6' }, SENDER),
    ).rejects.toThrow(/zero|greater/)
  })

  it('rejects negative amountPerPeriod', async () => {
    await expect(
      client.subscribe({ ...validSub, amountPerPeriod: -100n, orderId: 'sub-m-7' }, SENDER),
    ).rejects.toThrow()
  })

  it('rejects prepaidPeriods as float', async () => {
    await expect(
      client.subscribe({ ...validSub, prepaidPeriods: 2.5, orderId: 'sub-m-8' }, SENDER),
    ).rejects.toThrow()
  })
})

// ────────────────────────────────────────────────────────────
//  Invalid coin
// ────────────────────────────────────────────────────────────

describe('Monkey: Invalid coin', () => {
  let client: FloatSync

  beforeEach(() => {
    client = new FloatSync(baseConfig)
  })

  it('rejects unknown coin shorthand', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'DOGE', orderId: 'coin-m-1' }, SENDER),
    ).rejects.toThrow(/[Uu]nknown/)
  })

  it('accepts full coin type starting with 0x', async () => {
    // Full type passes through registry — may fail at getCoins but not at validation
    mockGetCoins.mockResolvedValue({
      data: [{ coinObjectId: '0xcustom1', balance: '999999' }],
    })

    const result = await client.pay(
      { amount: 1000n, coin: '0xcustom::token::TOKEN', orderId: 'coin-m-2' },
      SENDER,
    )
    expect(result.tx).toBeDefined()
  })
})

// ────────────────────────────────────────────────────────────
//  Query methods with invalid data
// ────────────────────────────────────────────────────────────

describe('Monkey: Query edge cases', () => {
  let client: FloatSync

  beforeEach(() => {
    client = new FloatSync(baseConfig)
  })

  it('getMerchant throws on null data', async () => {
    ;(client.suiClient.getObject as ReturnType<typeof vi.fn>).mockResolvedValue({ data: null })
    await expect(client.getMerchant()).rejects.toThrow(/not found/)
  })

  it('getMerchant throws on non-moveObject dataType', async () => {
    ;(client.suiClient.getObject as ReturnType<typeof vi.fn>).mockResolvedValue({
      data: { content: { dataType: 'package' } },
    })
    await expect(client.getMerchant()).rejects.toThrow(/not found/)
  })

  it('getSubscription throws on deleted object', async () => {
    ;(client.suiClient.getObject as ReturnType<typeof vi.fn>).mockResolvedValue({
      data: { content: null },
    })
    await expect(client.getSubscription('0xdeleted')).rejects.toThrow(/not found/)
  })

  it('getMerchant handles missing optional fields gracefully', async () => {
    ;(client.suiClient.getObject as ReturnType<typeof vi.fn>).mockResolvedValue({
      data: {
        content: {
          dataType: 'moveObject',
          fields: {}, // all fields missing
        },
      },
    })

    const info = await client.getMerchant()
    expect(info.owner).toBe('')
    expect(info.brandName).toBe('')
    expect(info.totalReceived).toBe(0n)
    expect(info.activeSubscriptions).toBe(0)
    expect(info.paused).toBe(false)
  })
})

// ────────────────────────────────────────────────────────────
//  Concurrent idempotency stress
// ────────────────────────────────────────────────────────────

describe('Monkey: Concurrent idempotency', () => {
  it('parallel pays with same orderId — first wins, rest get DUPLICATE_PENDING', async () => {
    const client = new FloatSync(baseConfig)

    // Fire 5 concurrent pays with same orderId
    const promises = Array.from({ length: 5 }, (_, i) =>
      client
        .pay({ amount: 1000n, coin: 'SUI', orderId: 'concurrent-001' }, SENDER)
        .then(() => 'ok' as const)
        .catch((e: Error) => e.message),
    )

    const results = await Promise.all(promises)

    // Exactly 1 should succeed, rest should get "already in progress"
    const successes = results.filter((r) => r === 'ok')
    const duplicates = results.filter((r) => typeof r === 'string' && r.includes('already in progress'))

    expect(successes).toHaveLength(1)
    expect(duplicates).toHaveLength(4)
  })

  it('different orderIds can proceed in parallel', async () => {
    const client = new FloatSync(baseConfig)

    const promises = Array.from({ length: 3 }, (_, i) =>
      client.pay({ amount: 1000n, coin: 'SUI', orderId: `parallel-${i}` }, SENDER),
    )

    const results = await Promise.all(promises)
    expect(results).toHaveLength(3)
    results.forEach((r) => expect(r.tx).toBeDefined())
  })
})
