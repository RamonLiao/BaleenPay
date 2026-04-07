import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import type { ReactNode } from 'react'

// ── Mocks ──

vi.mock('@mysten/sui/grpc', () => {
  class MockSuiGrpcClient {
    baseUrl: string
    network: string
    constructor(opts: { baseUrl: string; network: string }) {
      this.baseUrl = opts.baseUrl
      this.network = opts.network
    }
    async getObject() {
      return {
        object: {
          json: {
            owner: '0xowner',
            brand_name: 'TestBrand',
            total_received: '1000',
            idle_principal: '500',
            accrued_yield: '50',
            active_subscriptions: 2,
            paused_by_admin: false,
            paused_by_self: false,
          },
        },
      }
    }
    async getMoveFunction() {
      return { function: { name: 'pay_once_v2' } }
    }
    async listCoins() {
      return { objects: [], hasNextPage: false }
    }
    async getCoinMetadata() {
      return { coinMetadata: { decimals: 9 } }
    }
    async waitForTransaction() {
      return {}
    }
  }
  return { SuiGrpcClient: MockSuiGrpcClient }
})

vi.mock('@mysten/sui/graphql', () => {
  class MockSuiGraphQLClient {
    url: string
    network: string
    constructor(opts: { url: string; network: string }) {
      this.url = opts.url
      this.network = opts.network
    }
    async query() {
      return {
        data: {
          events: {
            nodes: [
              {
                type: { repr: '0xpkg123::events::PaymentReceivedV2' },
                contents: {
                  json: {
                    merchant_id: '0xmerchant456',
                    payer: '0xpayer1',
                    amount: '100',
                    payment_type: 0,
                    timestamp: '1700000000',
                    order_id: 'order-1',
                    coin_type: '0x2::sui::SUI',
                  },
                },
                sender: { address: '0xpayer1' },
              },
            ],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      }
    }
  }
  return { SuiGraphQLClient: MockSuiGraphQLClient }
})

// Mock dapp-kit-react
const mockSignAndExecuteTransaction = vi.fn()
const mockAccount = { address: '0xsender123' }

vi.mock('@mysten/dapp-kit-react', () => ({
  useDAppKit: () => ({
    signAndExecuteTransaction: mockSignAndExecuteTransaction,
  }),
  useCurrentAccount: () => mockAccount,
}))

// Mock @tanstack/react-query
const mockQueryData = { current: undefined as unknown }
const mockRefetchFn = vi.fn()
vi.mock('@tanstack/react-query', () => ({
  useQuery: (opts: { queryFn: () => Promise<unknown>; queryKey: unknown[] }) => {
    // Execute queryFn synchronously for test simplicity
    if (mockQueryData.current !== undefined) {
      return {
        data: mockQueryData.current,
        isLoading: false,
        error: null,
      }
    }
    return {
      data: undefined,
      isLoading: true,
      error: null,
    }
  },
  useQueryClient: () => ({
    invalidateQueries: mockRefetchFn,
  }),
}))

import { BaleenPayProvider, usePayment, useSubscription, useMerchant, usePaymentHistory } from '../src/index.js'

const testConfig = {
  network: 'testnet' as const,
  packageId: '0xpkg123',
  merchantId: '0xmerchant456',
}

function wrapper({ children }: { children: ReactNode }) {
  return (
    <BaleenPayProvider config={testConfig}>
      {children}
    </BaleenPayProvider>
  )
}

// ── usePayment ──

describe('usePayment', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('starts in idle state', () => {
    const { result } = renderHook(() => usePayment(), { wrapper })
    expect(result.current.status).toBe('idle')
    expect(result.current.error).toBeNull()
    expect(result.current.result).toBeNull()
  })

  it('transitions to success on successful payment', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xdigest123' },
    })

    const { result } = renderHook(() => usePayment(), { wrapper })

    await act(async () => {
      await result.current.pay({ amount: 100n, coin: 'SUI', orderId: 'order-1' })
    })

    expect(result.current.status).toBe('success')
    expect(result.current.result).toBe('0xdigest123')
    expect(result.current.error).toBeNull()
  })

  it('transitions to error on failed transaction', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      FailedTransaction: {
        status: { error: { message: 'Insufficient balance' } },
      },
    })

    const { result } = renderHook(() => usePayment(), { wrapper })

    await act(async () => {
      await result.current.pay({ amount: 100n, coin: 'SUI', orderId: 'order-2' })
    })

    expect(result.current.status).toBe('error')
    expect(result.current.error?.message).toBe('Insufficient balance')
    expect(result.current.result).toBeNull()
  })

  it('transitions to rejected on wallet rejection', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(
      new Error('User rejected the request'),
    )

    const { result } = renderHook(() => usePayment(), { wrapper })

    await act(async () => {
      await result.current.pay({ amount: 100n, coin: 'SUI', orderId: 'order-3' })
    })

    expect(result.current.status).toBe('rejected')
    expect(result.current.error?.message).toContain('rejected')
  })

  it('reset returns to idle', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xdigest456' },
    })

    const { result } = renderHook(() => usePayment(), { wrapper })

    await act(async () => {
      await result.current.pay({ amount: 100n, coin: 'SUI', orderId: 'order-4' })
    })

    expect(result.current.status).toBe('success')

    act(() => {
      result.current.reset()
    })

    expect(result.current.status).toBe('idle')
    expect(result.current.error).toBeNull()
    expect(result.current.result).toBeNull()
  })

  it('errors when wallet not connected', async () => {
    // Temporarily override account to null
    const origMock = vi.mocked(await import('@mysten/dapp-kit-react')).useCurrentAccount
    vi.mocked(await import('@mysten/dapp-kit-react')).useCurrentAccount = () => null as any

    const { result } = renderHook(() => usePayment(), { wrapper })

    await act(async () => {
      await result.current.pay({ amount: 100n, coin: 'SUI', orderId: 'order-5' })
    })

    expect(result.current.status).toBe('error')
    expect(result.current.error?.message).toContain('Wallet not connected')

    // Restore
    vi.mocked(await import('@mysten/dapp-kit-react')).useCurrentAccount = origMock
  })

  it('signAndExecuteTransaction is called with the built tx', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xdig' },
    })

    const { result } = renderHook(() => usePayment(), { wrapper })

    await act(async () => {
      await result.current.pay({ amount: 50n, coin: 'SUI', orderId: 'order-6' })
    })

    expect(mockSignAndExecuteTransaction).toHaveBeenCalledTimes(1)
    expect(mockSignAndExecuteTransaction).toHaveBeenCalledWith(
      expect.objectContaining({ transaction: expect.anything() }),
    )
  })
})

// ── useSubscription ──

describe('useSubscription', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('starts in idle state', () => {
    const { result } = renderHook(() => useSubscription(), { wrapper })
    expect(result.current.status).toBe('idle')
  })

  it('subscribe transitions to success', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xsubdigest' },
    })

    const { result } = renderHook(() => useSubscription(), { wrapper })

    await act(async () => {
      await result.current.subscribe({
        amountPerPeriod: 10n,
        periodMs: 86400000,
        prepaidPeriods: 3,
        coin: 'SUI',
        orderId: 'sub-1',
      })
    })

    expect(result.current.status).toBe('success')
    expect(result.current.result).toBe('0xsubdigest')
  })

  it('cancel transitions to success', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xcanceldigest' },
    })

    const { result } = renderHook(() => useSubscription(), { wrapper })

    await act(async () => {
      await result.current.cancel('0xsub123', '0x2::sui::SUI')
    })

    expect(result.current.status).toBe('success')
    expect(result.current.result).toBe('0xcanceldigest')
  })

  it('process transitions to success', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xprocessdigest' },
    })

    const { result } = renderHook(() => useSubscription(), { wrapper })

    await act(async () => {
      await result.current.process('0xsub456', '0x2::sui::SUI')
    })

    expect(result.current.status).toBe('success')
    expect(result.current.result).toBe('0xprocessdigest')
  })

  it('handles error on subscribe failure', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(new Error('Network error'))

    const { result } = renderHook(() => useSubscription(), { wrapper })

    await act(async () => {
      await result.current.subscribe({
        amountPerPeriod: 10n,
        periodMs: 86400000,
        prepaidPeriods: 3,
        coin: 'SUI',
        orderId: 'sub-fail',
      })
    })

    expect(result.current.status).toBe('error')
    expect(result.current.error?.message).toBe('Network error')
  })

  it('reset clears state', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xd' },
    })

    const { result } = renderHook(() => useSubscription(), { wrapper })

    await act(async () => {
      await result.current.cancel('0xsub', '0x2::sui::SUI')
    })

    expect(result.current.status).toBe('success')

    act(() => result.current.reset())

    expect(result.current.status).toBe('idle')
    expect(result.current.result).toBeNull()
  })
})

// ── useMerchant ──

describe('useMerchant', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('returns loading state initially', () => {
    const { result } = renderHook(() => useMerchant(), { wrapper })
    expect(result.current.isLoading).toBe(true)
    expect(result.current.merchant).toBeUndefined()
  })

  it('returns merchant data when loaded', () => {
    mockQueryData.current = {
      merchantId: '0xmerchant456',
      owner: '0xowner',
      brandName: 'TestBrand',
      totalReceived: 1000n,
      idlePrincipal: 500n,
      accruedYield: 50n,
      activeSubscriptions: 2,
      pausedByAdmin: false,
      pausedBySelf: false,
    }

    const { result } = renderHook(() => useMerchant(), { wrapper })
    expect(result.current.isLoading).toBe(false)
    expect(result.current.merchant?.brandName).toBe('TestBrand')
    expect(result.current.merchant?.totalReceived).toBe(1000n)
  })

  it('accepts custom merchantId', () => {
    mockQueryData.current = {
      merchantId: '0xcustom',
      owner: '0xowner2',
      brandName: 'Custom',
      totalReceived: 0n,
      idlePrincipal: 0n,
      accruedYield: 0n,
      activeSubscriptions: 0,
      pausedByAdmin: false,
      pausedBySelf: false,
    }

    const { result } = renderHook(() => useMerchant('0xcustom'), { wrapper })
    expect(result.current.merchant?.merchantId).toBe('0xcustom')
  })

  it('refetch calls invalidateQueries', () => {
    mockQueryData.current = {
      merchantId: '0xmerchant456',
      owner: '0xowner',
      brandName: 'Test',
      totalReceived: 0n,
      idlePrincipal: 0n,
      accruedYield: 0n,
      activeSubscriptions: 0,
      pausedByAdmin: false,
      pausedBySelf: false,
    }

    const { result } = renderHook(() => useMerchant(), { wrapper })
    result.current.refetch()
    expect(mockRefetchFn).toHaveBeenCalledWith(
      expect.objectContaining({
        queryKey: ['baleenpay', 'merchant', '0xmerchant456'],
      }),
    )
  })
})

// ── usePaymentHistory ──

describe('usePaymentHistory', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('returns loading state initially', () => {
    const { result } = renderHook(() => usePaymentHistory(), { wrapper })
    expect(result.current.isLoading).toBe(true)
    expect(result.current.events).toEqual([])
  })

  it('returns events when loaded', () => {
    mockQueryData.current = {
      events: [
        { type: 'payment.received', merchantId: '0xm', amount: 100n, orderId: 'o1' },
      ],
      hasNextPage: false,
    }

    const { result } = renderHook(() => usePaymentHistory(), { wrapper })
    expect(result.current.isLoading).toBe(false)
    expect(result.current.events).toHaveLength(1)
    expect(result.current.events[0].orderId).toBe('o1')
  })

  it('hasNextPage reflects data', () => {
    mockQueryData.current = {
      events: [],
      hasNextPage: true,
      nextCursor: 'cursor-1',
    }

    const { result } = renderHook(() => usePaymentHistory(), { wrapper })
    expect(result.current.hasNextPage).toBe(true)
  })

  it('defaults to enabled=true', () => {
    const { result } = renderHook(() => usePaymentHistory(), { wrapper })
    // Hook runs — it's in loading state (not skipped)
    expect(result.current.isLoading).toBe(true)
  })

  it('accepts custom options', () => {
    mockQueryData.current = {
      events: [],
      hasNextPage: false,
    }

    const { result } = renderHook(
      () => usePaymentHistory({ limit: 5, order: 'asc', payer: '0xpayer' }),
      { wrapper },
    )
    expect(result.current.isLoading).toBe(false)
  })

  it('refetch clears cursor and invalidates queries', () => {
    mockQueryData.current = {
      events: [],
      hasNextPage: false,
    }

    const { result } = renderHook(() => usePaymentHistory(), { wrapper })
    result.current.refetch()
    expect(mockRefetchFn).toHaveBeenCalled()
  })
})
