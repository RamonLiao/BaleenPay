import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, act } from '@testing-library/react'
import type { ReactNode } from 'react'

// ── Mocks (same as hooks.test.tsx) ──

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

const mockSignAndExecuteTransaction = vi.fn()
const mockAccount = { address: '0xsender123' }

vi.mock('@mysten/dapp-kit-react', () => ({
  useDAppKit: () => ({
    signAndExecuteTransaction: mockSignAndExecuteTransaction,
  }),
  useCurrentAccount: () => mockAccount,
}))

const mockQueryData = { current: undefined as unknown }
const mockRefetchFn = vi.fn()
vi.mock('@tanstack/react-query', () => ({
  useQuery: (opts: { queryFn: () => Promise<unknown>; queryKey: unknown[] }) => {
    if (mockQueryData.current !== undefined) {
      return { data: mockQueryData.current, isLoading: false, error: null }
    }
    return { data: undefined, isLoading: true, error: null }
  },
  useQueryClient: () => ({
    invalidateQueries: mockRefetchFn,
  }),
}))

import {
  FloatSyncProvider,
  CheckoutButton,
  PaymentForm,
  SubscribeButton,
  MerchantBadge,
} from '../src/index.js'

const testConfig = {
  network: 'testnet' as const,
  packageId: '0xpkg123',
  merchantId: '0xmerchant456',
}

function Wrapper({ children }: { children: ReactNode }) {
  return <FloatSyncProvider config={testConfig}>{children}</FloatSyncProvider>
}

// ── CheckoutButton ──

describe('CheckoutButton', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('renders default label "Pay"', () => {
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-1" />
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toHaveTextContent('Pay')
  })

  it('renders custom children', () => {
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-1">
          Buy Now
        </CheckoutButton>
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toHaveTextContent('Buy Now')
  })

  it('renders render-prop children with state', () => {
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-1">
          {(state) => <span>Status: {state.status}</span>}
        </CheckoutButton>
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toHaveTextContent('Status: idle')
  })

  it('has data-status attribute', () => {
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-1" />
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toHaveAttribute('data-status', 'idle')
  })

  it('transitions to success on click', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xdigest1' },
    })

    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-cb1" />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    expect(screen.getByRole('button')).toHaveAttribute('data-status', 'success')
    expect(screen.getByRole('button')).toHaveTextContent('Paid!')
  })

  it('calls onSuccess with digest', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xdigest2' },
    })

    const onSuccess = vi.fn()
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-cb2" onSuccess={onSuccess} />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    expect(onSuccess).toHaveBeenCalledWith('0xdigest2')
  })

  it('calls onError on failure', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(new Error('tx failed'))

    const onError = vi.fn()
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-cb3" onError={onError} />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    expect(onError).toHaveBeenCalledWith(expect.objectContaining({ message: 'tx failed' }))
    expect(screen.getByRole('button')).toHaveAttribute('data-status', 'error')
  })

  it('calls onError on wallet rejection', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(new Error('User rejected'))

    const onError = vi.fn()
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-cb4" onError={onError} />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    expect(onError).toHaveBeenCalled()
    expect(screen.getByRole('button')).toHaveAttribute('data-status', 'rejected')
    expect(screen.getByRole('button')).toHaveTextContent('Rejected')
  })

  it('disables button when disabled prop is true', () => {
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-1" disabled />
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toBeDisabled()
  })

  it('applies className', () => {
    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-1" className="my-btn" />
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toHaveClass('my-btn')
  })

  it('shows retry label after error and button is re-clickable', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(new Error('network error'))

    render(
      <Wrapper>
        <CheckoutButton amount={100n} coin="SUI" orderId="order-retry" />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    expect(screen.getByRole('button')).toHaveAttribute('data-status', 'error')
    expect(screen.getByRole('button')).toHaveTextContent('Failed')
    // Button should NOT be disabled — user can retry
    expect(screen.getByRole('button')).not.toBeDisabled()
  })
})

// ── PaymentForm ──

describe('PaymentForm', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('renders amount input, coin selector, order input, and pay button', () => {
    render(
      <Wrapper>
        <PaymentForm />
      </Wrapper>,
    )
    expect(screen.getByLabelText('Amount')).toBeInTheDocument()
    expect(screen.getByLabelText('Coin')).toBeInTheDocument()
    expect(screen.getByLabelText('Order ID')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Pay' })).toBeInTheDocument()
  })

  it('hides order input when orderId is provided externally', () => {
    render(
      <Wrapper>
        <PaymentForm orderId="ext-order" />
      </Wrapper>,
    )
    expect(screen.queryByLabelText('Order ID')).not.toBeInTheDocument()
  })

  it('renders coin dropdown for multiple coins', () => {
    render(
      <Wrapper>
        <PaymentForm coins={['SUI', 'USDC']} />
      </Wrapper>,
    )
    const select = screen.getByLabelText('Coin') as HTMLSelectElement
    expect(select.tagName).toBe('SELECT')
    expect(select.options).toHaveLength(2)
  })

  it('renders readonly input for single coin', () => {
    render(
      <Wrapper>
        <PaymentForm coins={['USDC']} />
      </Wrapper>,
    )
    const input = screen.getByLabelText('Coin') as HTMLInputElement
    expect(input.tagName).toBe('INPUT')
    expect(input.readOnly).toBe(true)
    expect(input.value).toBe('USDC')
  })

  it('submit button is disabled when amount is empty', () => {
    render(
      <Wrapper>
        <PaymentForm orderId="o1" />
      </Wrapper>,
    )
    expect(screen.getByRole('button', { name: 'Pay' })).toBeDisabled()
  })

  it('transitions to success on valid submit', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xform-digest' },
    })

    const onSuccess = vi.fn()
    render(
      <Wrapper>
        <PaymentForm orderId="form-order" onSuccess={onSuccess} />
      </Wrapper>,
    )

    fireEvent.change(screen.getByLabelText('Amount'), { target: { value: '100' } })

    await act(async () => {
      fireEvent.submit(screen.getByRole('button', { name: 'Pay' }).closest('form')!)
    })

    expect(onSuccess).toHaveBeenCalledWith('0xform-digest')
    expect(screen.getByText('Payment confirmed')).toBeInTheDocument()
  })

  it('shows error message on failure', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(new Error('Insufficient balance'))

    render(
      <Wrapper>
        <PaymentForm orderId="form-err" />
      </Wrapper>,
    )

    fireEvent.change(screen.getByLabelText('Amount'), { target: { value: '999' } })

    await act(async () => {
      fireEvent.submit(screen.getByRole('button', { name: 'Pay' }).closest('form')!)
    })

    expect(screen.getByRole('alert')).toHaveTextContent('Insufficient balance')
  })

  it('applies className and data-floatsync', () => {
    render(
      <Wrapper>
        <PaymentForm className="my-form" />
      </Wrapper>,
    )
    const form = document.querySelector('[data-floatsync="payment-form"]')
    expect(form).toHaveClass('my-form')
  })
})

// ── SubscribeButton ──

describe('SubscribeButton', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  const subProps = {
    amountPerPeriod: 10n,
    periodMs: 86400000,
    prepaidPeriods: 3,
    coin: 'SUI',
    orderId: 'sub-1',
  } as const

  it('renders default label "Subscribe"', () => {
    render(
      <Wrapper>
        <SubscribeButton {...subProps} />
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toHaveTextContent('Subscribe')
  })

  it('transitions to success on click', async () => {
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xsubdigest' },
    })

    const onSuccess = vi.fn()
    render(
      <Wrapper>
        <SubscribeButton {...subProps} onSuccess={onSuccess} />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    expect(screen.getByRole('button')).toHaveTextContent('Subscribed!')
    expect(onSuccess).toHaveBeenCalledWith('0xsubdigest')
  })

  it('calls onError on failure', async () => {
    mockSignAndExecuteTransaction.mockRejectedValue(new Error('sub failed'))

    const onError = vi.fn()
    render(
      <Wrapper>
        <SubscribeButton {...subProps} onError={onError} />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    expect(onError).toHaveBeenCalledWith(expect.objectContaining({ message: 'sub failed' }))
  })

  it('supports render-prop children', () => {
    render(
      <Wrapper>
        <SubscribeButton {...subProps}>
          {(state) => <span>Sub: {state.status}</span>}
        </SubscribeButton>
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toHaveTextContent('Sub: idle')
  })

  it('disables when disabled prop is true', () => {
    render(
      <Wrapper>
        <SubscribeButton {...subProps} disabled />
      </Wrapper>,
    )
    expect(screen.getByRole('button')).toBeDisabled()
  })
})

// ── MerchantBadge ──

describe('MerchantBadge', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('shows loading state initially', () => {
    render(
      <Wrapper>
        <MerchantBadge />
      </Wrapper>,
    )
    expect(screen.getByText('Loading...')).toBeInTheDocument()
    expect(document.querySelector('[data-loading="true"]')).toBeInTheDocument()
  })

  it('displays merchant info when loaded', () => {
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

    render(
      <Wrapper>
        <MerchantBadge />
      </Wrapper>,
    )

    expect(screen.getByText('TestBrand')).toBeInTheDocument()
    expect(screen.getByText('Active')).toBeInTheDocument()
    expect(screen.getByText('1000')).toBeInTheDocument()
    expect(screen.getByText('2')).toBeInTheDocument()
  })

  it('shows paused status', () => {
    mockQueryData.current = {
      merchantId: '0xmerchant456',
      owner: '0xowner',
      brandName: 'PausedBrand',
      totalReceived: 0n,
      idlePrincipal: 0n,
      accruedYield: 0n,
      activeSubscriptions: 0,
      pausedByAdmin: true,
      pausedBySelf: false,
    }

    render(
      <Wrapper>
        <MerchantBadge />
      </Wrapper>,
    )

    expect(screen.getByText('Paused')).toBeInTheDocument()
    expect(document.querySelector('[data-paused]')).toBeInTheDocument()
  })

  it('supports render-prop children', () => {
    mockQueryData.current = {
      merchantId: '0xm',
      owner: '0xo',
      brandName: 'Custom',
      totalReceived: 500n,
      idlePrincipal: 0n,
      accruedYield: 0n,
      activeSubscriptions: 1,
      pausedByAdmin: false,
      pausedBySelf: false,
    }

    render(
      <Wrapper>
        <MerchantBadge>
          {(info, loading) => (
            <div data-testid="custom">{loading ? 'wait' : info.brandName}</div>
          )}
        </MerchantBadge>
      </Wrapper>,
    )

    expect(screen.getByTestId('custom')).toHaveTextContent('Custom')
  })

  it('applies className', () => {
    mockQueryData.current = {
      merchantId: '0xm',
      owner: '0xo',
      brandName: 'X',
      totalReceived: 0n,
      idlePrincipal: 0n,
      accruedYield: 0n,
      activeSubscriptions: 0,
      pausedByAdmin: false,
      pausedBySelf: false,
    }

    render(
      <Wrapper>
        <MerchantBadge className="badge" />
      </Wrapper>,
    )

    expect(document.querySelector('[data-floatsync="merchant-badge"]')).toHaveClass('badge')
  })

  it('shows "No merchant data" when empty', () => {
    // mockQueryData is undefined → isLoading = true, but we need a "loaded with null" state
    // We simulate by setting data to null-ish
    mockQueryData.current = null

    render(
      <Wrapper>
        <MerchantBadge />
      </Wrapper>,
    )

    // Since null is falsy and isLoading=false, it should show empty state
    expect(screen.getByText('No merchant data')).toBeInTheDocument()
  })
})

// ── Monkey Tests ──

describe('Component Monkey Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockQueryData.current = undefined
  })

  it('CheckoutButton: rapid double-click does not fire twice', async () => {
    mockSignAndExecuteTransaction.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve({ Transaction: { digest: '0xd' } }), 50)),
    )

    render(
      <Wrapper>
        <CheckoutButton amount={1n} coin="SUI" orderId="dbl-click" />
      </Wrapper>,
    )

    const btn = screen.getByRole('button')

    // Click once — it should start processing and become disabled
    await act(async () => {
      fireEvent.click(btn)
    })

    // Button should now be disabled during processing
    // Try clicking again — should be a no-op since disabled
    fireEvent.click(btn)

    // Wait for the first transaction to complete
    await act(async () => {
      await new Promise((r) => setTimeout(r, 100))
    })

    expect(mockSignAndExecuteTransaction).toHaveBeenCalledTimes(1)
  })

  it('CheckoutButton: amount=0 passes through to SDK (SDK validates)', async () => {
    const onError = vi.fn()
    mockSignAndExecuteTransaction.mockResolvedValue({
      Transaction: { digest: '0xzero' },
    })

    render(
      <Wrapper>
        <CheckoutButton amount={0n} coin="SUI" orderId="zero-amt" onError={onError} />
      </Wrapper>,
    )

    await act(async () => {
      fireEvent.click(screen.getByRole('button'))
    })

    // Either SDK rejects (error) or it passes through (success) — component handles both
    const btn = screen.getByRole('button')
    const status = btn.getAttribute('data-status')
    expect(['error', 'success']).toContain(status)
  })

  it('PaymentForm: prevents submit with whitespace-only orderId', async () => {
    render(
      <Wrapper>
        <PaymentForm />
      </Wrapper>,
    )

    fireEvent.change(screen.getByLabelText('Amount'), { target: { value: '100' } })
    fireEvent.change(screen.getByLabelText('Order ID'), { target: { value: '   ' } })

    await act(async () => {
      fireEvent.submit(screen.getByRole('button', { name: 'Pay' }).closest('form')!)
    })

    // Should not call signAndExecuteTransaction
    expect(mockSignAndExecuteTransaction).not.toHaveBeenCalled()
  })

  it('PaymentForm: prevents submit with negative amount', async () => {
    render(
      <Wrapper>
        <PaymentForm orderId="neg-test" />
      </Wrapper>,
    )

    fireEvent.change(screen.getByLabelText('Amount'), { target: { value: '-5' } })

    await act(async () => {
      fireEvent.submit(screen.getByRole('button').closest('form')!)
    })

    expect(mockSignAndExecuteTransaction).not.toHaveBeenCalled()
  })

  it('PaymentForm: prevents submit with non-numeric amount', async () => {
    render(
      <Wrapper>
        <PaymentForm orderId="nan-test" />
      </Wrapper>,
    )

    fireEvent.change(screen.getByLabelText('Amount'), { target: { value: 'abc' } })

    await act(async () => {
      fireEvent.submit(screen.getByRole('button').closest('form')!)
    })

    expect(mockSignAndExecuteTransaction).not.toHaveBeenCalled()
  })

  it('SubscribeButton: rapid clicks during processing are no-ops', async () => {
    mockSignAndExecuteTransaction.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve({ Transaction: { digest: '0xs' } }), 50)),
    )

    render(
      <Wrapper>
        <SubscribeButton
          amountPerPeriod={10n}
          periodMs={86400000}
          prepaidPeriods={3}
          coin="SUI"
          orderId="rapid-sub"
        />
      </Wrapper>,
    )

    const btn = screen.getByRole('button')
    await act(async () => {
      fireEvent.click(btn)
    })

    // During processing, button disabled
    fireEvent.click(btn)
    fireEvent.click(btn)

    await act(async () => {
      await new Promise((r) => setTimeout(r, 100))
    })

    expect(mockSignAndExecuteTransaction).toHaveBeenCalledTimes(1)
  })

  it('MerchantBadge: render-prop with loading=true does not crash', () => {
    // data is undefined → loading
    render(
      <Wrapper>
        <MerchantBadge>
          {(info, loading) => (
            <span data-testid="rp">{loading ? 'loading...' : info?.brandName ?? 'none'}</span>
          )}
        </MerchantBadge>
      </Wrapper>,
    )

    expect(screen.getByTestId('rp')).toHaveTextContent('loading...')
  })
})
