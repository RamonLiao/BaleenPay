import { describe, it, expect, vi, beforeEach } from 'vitest'
import {
  mockGetObject,
  mockListCoins,
  mockGetMoveFunction,
  setupGrpcMock,
  setupGraphQLMock,
  mockV2Available,
  mockDefaultCoins,
} from './_mocks.js'
import { BaleenPay } from '../src/client.js'
import { ValidationError } from '../src/errors.js'

// Hoist mocks before any imports that use them
setupGrpcMock()
setupGraphQLMock()

const SENDER = '0xsender'
const baseConfig = {
  network: 'testnet' as const,
  packageId: '0xpkg_monkey',
  merchantId: '0xmerchant_monkey',
}

beforeEach(() => {
  vi.clearAllMocks()
  // Default: v2 available
  mockV2Available()
  mockDefaultCoins()
})

// ────────────────────────────────────────────────────────────
//  Invalid config
// ────────────────────────────────────────────────────────────

describe('Monkey: Invalid config', () => {
  it('throws on empty packageId', () => {
    expect(() => new BaleenPay({ ...baseConfig, packageId: '' })).toThrow(ValidationError)
  })

  it('throws on empty merchantId', () => {
    expect(() => new BaleenPay({ ...baseConfig, merchantId: '' })).toThrow(ValidationError)
  })

  it('throws on missing network', () => {
    expect(() => new BaleenPay({ ...baseConfig, network: '' as 'testnet' })).toThrow(ValidationError)
  })

  it('throws on undefined packageId', () => {
    expect(() => new BaleenPay({ ...baseConfig, packageId: undefined as unknown as string })).toThrow()
  })

  it('throws on undefined merchantId', () => {
    expect(() => new BaleenPay({ ...baseConfig, merchantId: undefined as unknown as string })).toThrow()
  })
})

// ────────────────────────────────────────────────────────────
//  Invalid orderId
// ────────────────────────────────────────────────────────────

describe('Monkey: Invalid orderId', () => {
  let client: BaleenPay

  beforeEach(() => {
    client = new BaleenPay(baseConfig)
  })

  it('rejects empty orderId', async () => {
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
  let client: BaleenPay

  beforeEach(() => {
    client = new BaleenPay(baseConfig)
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
    mockListCoins.mockResolvedValue({
      objects: [{ objectId: '0xwhale', balance: '18446744073709551615' }],
    })

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
  let client: BaleenPay

  beforeEach(() => {
    client = new BaleenPay(baseConfig)
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
  let client: BaleenPay

  beforeEach(() => {
    client = new BaleenPay(baseConfig)
  })

  it('rejects unknown coin shorthand', async () => {
    await expect(
      client.pay({ amount: 1000n, coin: 'DOGE', orderId: 'coin-m-1' }, SENDER),
    ).rejects.toThrow(/[Uu]nknown/)
  })

  it('accepts full coin type starting with 0x', async () => {
    mockListCoins.mockResolvedValue({
      objects: [{ objectId: '0xcustom1', balance: '999999' }],
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
  let client: BaleenPay

  beforeEach(() => {
    client = new BaleenPay(baseConfig)
  })

  it('getMerchant throws on null object', async () => {
    mockGetObject.mockResolvedValue({ object: null })
    await expect(client.getMerchant()).rejects.toThrow(/not found/)
  })

  it('getMerchant throws on null json', async () => {
    mockGetObject.mockResolvedValue({ object: { json: null } })
    await expect(client.getMerchant()).rejects.toThrow(/not found/)
  })

  it('getSubscription throws on deleted object', async () => {
    mockGetObject.mockResolvedValue({ object: null })
    await expect(client.getSubscription('0xdeleted')).rejects.toThrow(/not found/)
  })

  it('getMerchant handles missing optional fields gracefully', async () => {
    mockGetObject.mockResolvedValue({
      object: { json: {} },
    })

    const info = await client.getMerchant()
    expect(info.owner).toBe('')
    expect(info.brandName).toBe('')
    expect(info.totalReceived).toBe(0n)
    expect(info.activeSubscriptions).toBe(0)
    expect(info.pausedByAdmin).toBe(false)
    expect(info.pausedBySelf).toBe(false)
  })
})

// ────────────────────────────────────────────────────────────
//  Concurrent idempotency stress
// ────────────────────────────────────────────────────────────

describe('Monkey: Concurrent idempotency', () => {
  it('parallel pays with same orderId — first wins, rest get DUPLICATE_PENDING', async () => {
    const client = new BaleenPay(baseConfig)

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
    const client = new BaleenPay(baseConfig)

    const promises = Array.from({ length: 3 }, (_, i) =>
      client.pay({ amount: 1000n, coin: 'SUI', orderId: `parallel-${i}` }, SENDER),
    )

    const results = await Promise.all(promises)
    expect(results).toHaveLength(3)
    results.forEach((r) => expect(r.tx).toBeDefined())
  })
})
