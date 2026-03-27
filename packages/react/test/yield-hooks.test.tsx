import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
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
            balance: '2000',
          },
        },
      }
    }
    async getMoveFunction() {
      return { function: { name: 'claim_yield_v2' } }
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
      return { data: { events: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } } } }
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

import {
  FloatSyncProvider,
  useYieldInfo,
  useYieldHistory,
  useClaimYield,
} from '../src/index.js'

const testConfig = {
  network: 'testnet' as const,
  packageId: '0xpkg123',
  merchantId: '0xmerchant456',
  yieldVaultId: '0xyieldvault789',
}

function wrapper({ children }: { children: ReactNode }) {
  return (
    <FloatSyncProvider config={testConfig}>
      {children}
    </FloatSyncProvider>
  )
}

// ── useYieldInfo ──

describe('useYieldInfo', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('returns loading state initially', () => {
    const { result } = renderHook(() => useYieldInfo(), { wrapper })
    expect(result.current.isLoading).toBe(true)
    expect(result.current.yieldInfo).toBeUndefined()
    expect(result.current.error).toBeNull()
  })

  it('returns yield info when loaded', () => {
    mockQueryData.current = {
      idlePrincipal: 500n,
      accruedYield: 50n,
      claimableUsdb: 30n,
      estimatedApy: 0.05,
      vaultBalance: 2000n,
    }

    const { result } = renderHook(() => useYieldInfo(), { wrapper })
    expect(result.current.isLoading).toBe(false)
    expect(result.current.yieldInfo?.idlePrincipal).toBe(500n)
    expect(result.current.yieldInfo?.accruedYield).toBe(50n)
    expect(result.current.yieldInfo?.estimatedApy).toBe(0.05)
    expect(result.current.yieldInfo?.vaultBalance).toBe(2000n)
  })

  it('accepts custom merchantId', () => {
    mockQueryData.current = {
      idlePrincipal: 0n,
      accruedYield: 0n,
      claimableUsdb: 0n,
      estimatedApy: 0,
      vaultBalance: 0n,
    }

    const { result } = renderHook(() => useYieldInfo('0xcustom'), { wrapper })
    expect(result.current.isLoading).toBe(false)
    expect(result.current.yieldInfo).toBeDefined()
  })

  it('refetch calls invalidateQueries', () => {
    mockQueryData.current = {
      idlePrincipal: 0n,
      accruedYield: 0n,
      claimableUsdb: 0n,
      estimatedApy: 0,
      vaultBalance: 0n,
    }

    const { result } = renderHook(() => useYieldInfo(), { wrapper })
    result.current.refetch()
    expect(mockRefetchFn).toHaveBeenCalledWith(
      expect.objectContaining({
        queryKey: ['floatsync', 'yield-info', '0xmerchant456'],
      }),
    )
  })
})

// ── useYieldHistory ──

describe('useYieldHistory', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('returns loading state initially', () => {
    const { result } = renderHook(() => useYieldHistory(), { wrapper })
    expect(result.current.isLoading).toBe(true)
    expect(result.current.dataPoints).toEqual([])
    expect(result.current.claimEvents).toEqual([])
  })

  it('returns empty data for MVP stub', () => {
    mockQueryData.current = { dataPoints: [], claimEvents: [] }

    const { result } = renderHook(() => useYieldHistory(), { wrapper })
    expect(result.current.isLoading).toBe(false)
    expect(result.current.dataPoints).toEqual([])
    expect(result.current.claimEvents).toEqual([])
    expect(result.current.error).toBeNull()
  })

  it('accepts custom merchantId', () => {
    mockQueryData.current = { dataPoints: [], claimEvents: [] }

    const { result } = renderHook(() => useYieldHistory('0xcustom'), { wrapper })
    expect(result.current.isLoading).toBe(false)
  })
})

// ── useClaimYield ──

describe('useClaimYield', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('starts in idle state', () => {
    const { result } = renderHook(() => useClaimYield(), { wrapper })
    expect(result.current.status).toBe('idle')
    expect(result.current.error).toBeNull()
    expect(result.current.txDigest).toBeNull()
  })

  it('transitions to success on successful claim', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xclaimdigest' },
    })

    const { result } = renderHook(() => useClaimYield(), { wrapper })

    await act(async () => {
      await result.current.claim('0xcap123')
    })

    expect(result.current.status).toBe('success')
    expect(result.current.txDigest).toBe('0xclaimdigest')
    expect(result.current.error).toBeNull()
  })

  it('transitions to error on failed transaction', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      FailedTransaction: {
        status: { error: { message: 'Insufficient yield' } },
      },
    })

    const { result } = renderHook(() => useClaimYield(), { wrapper })

    await act(async () => {
      await result.current.claim('0xcap123')
    })

    expect(result.current.status).toBe('error')
    expect(result.current.error?.message).toBe('Insufficient yield')
    expect(result.current.txDigest).toBeNull()
  })

  it('transitions to rejected on wallet rejection', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(
      new Error('User rejected the request'),
    )

    const { result } = renderHook(() => useClaimYield(), { wrapper })

    await act(async () => {
      await result.current.claim('0xcap123')
    })

    expect(result.current.status).toBe('rejected')
    expect(result.current.error?.message).toContain('rejected')
  })

  it('errors when wallet not connected', async () => {
    const origMock = vi.mocked(await import('@mysten/dapp-kit-react')).useCurrentAccount
    vi.mocked(await import('@mysten/dapp-kit-react')).useCurrentAccount = () => null as any

    const { result } = renderHook(() => useClaimYield(), { wrapper })

    await act(async () => {
      await result.current.claim('0xcap123')
    })

    expect(result.current.status).toBe('error')
    expect(result.current.error?.message).toContain('Wallet not connected')

    // Restore
    vi.mocked(await import('@mysten/dapp-kit-react')).useCurrentAccount = origMock
  })

  it('reset returns to idle', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xclaimdigest2' },
    })

    const { result } = renderHook(() => useClaimYield(), { wrapper })

    await act(async () => {
      await result.current.claim('0xcap456')
    })

    expect(result.current.status).toBe('success')

    act(() => {
      result.current.reset()
    })

    expect(result.current.status).toBe('idle')
    expect(result.current.error).toBeNull()
    expect(result.current.txDigest).toBeNull()
  })

  it('signAndExecuteTransaction is called with the built tx', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xdig' },
    })

    const { result } = renderHook(() => useClaimYield(), { wrapper })

    await act(async () => {
      await result.current.claim('0xcap789')
    })

    expect(mockSignAndExecuteTransaction).toHaveBeenCalledTimes(1)
    expect(mockSignAndExecuteTransaction).toHaveBeenCalledWith(
      expect.objectContaining({ transaction: expect.anything() }),
    )
  })
})
