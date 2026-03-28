import { describe, it, expect, vi } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { render, screen } from '@testing-library/react'
import { BaleenPayProvider, useBaleenPay, BaleenPayContext } from '../src/index.js'
import { BaleenPay } from '@baleenpay/sdk'
import type { ReactNode } from 'react'

// ── Mock SuiJsonRpcClient so BaleenPay constructor works ──
vi.mock('@mysten/sui/jsonRpc', () => {
  class MockSuiJsonRpcClient {
    url: string
    constructor(opts: { url: string; network?: string }) {
      this.url = opts.url
    }
  }
  return {
    SuiJsonRpcClient: MockSuiJsonRpcClient,
    getJsonRpcFullnodeUrl: (network: string) => `https://${network}.sui.io`,
  }
})

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

// ── Provider rendering ──

describe('BaleenPayProvider', () => {
  it('renders children', () => {
    render(
      <BaleenPayProvider config={testConfig}>
        <div data-testid="child">hello</div>
      </BaleenPayProvider>,
    )
    expect(screen.getByTestId('child')).toBeDefined()
    expect(screen.getByTestId('child').textContent).toBe('hello')
  })

  it('provides a BaleenPay client via context', () => {
    const { result } = renderHook(() => useBaleenPay(), { wrapper })
    expect(result.current).toBeInstanceOf(BaleenPay)
  })

  it('client has correct config', () => {
    const { result } = renderHook(() => useBaleenPay(), { wrapper })
    expect(result.current.config.network).toBe('testnet')
    expect(result.current.config.packageId).toBe('0xpkg123')
    expect(result.current.config.merchantId).toBe('0xmerchant456')
  })

  it('returns stable client reference on re-render with same config', () => {
    const refs: BaleenPay[] = []
    const { rerender } = renderHook(() => {
      const client = useBaleenPay()
      refs.push(client)
      return client
    }, { wrapper })

    rerender()
    expect(refs.length).toBe(2)
    expect(refs[0]).toBe(refs[1]) // same reference = useMemo working
  })

  it('creates new client when packageId changes', () => {
    const refs: BaleenPay[] = []
    let cfg = { ...testConfig }

    function DynamicWrapper({ children }: { children: ReactNode }) {
      return (
        <BaleenPayProvider config={cfg}>
          {children}
        </BaleenPayProvider>
      )
    }

    const { rerender } = renderHook(() => {
      const client = useBaleenPay()
      refs.push(client)
      return client
    }, { wrapper: DynamicWrapper })

    cfg = { ...testConfig, packageId: '0xnewpkg' }
    rerender()

    expect(refs.length).toBe(2)
    expect(refs[0]).not.toBe(refs[1])
    expect(refs[1].config.packageId).toBe('0xnewpkg')
  })

  it('passes options to BaleenPay client', () => {
    function WrapperWithOptions({ children }: { children: ReactNode }) {
      return (
        <BaleenPayProvider config={testConfig} options={{ pendingTtlMs: 30000 }}>
          {children}
        </BaleenPayProvider>
      )
    }

    const { result } = renderHook(() => useBaleenPay(), { wrapper: WrapperWithOptions })
    // Client was created successfully with options — no throw
    expect(result.current).toBeInstanceOf(BaleenPay)
  })
})

// ── useBaleenPay ──

describe('useBaleenPay', () => {
  it('throws when used outside provider', () => {
    // Suppress React error boundary console noise
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})

    expect(() => {
      renderHook(() => useBaleenPay())
    }).toThrow('useBaleenPay must be used within a <BaleenPayProvider>')

    spy.mockRestore()
  })

  it('error message mentions BaleenPayProvider', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})

    try {
      renderHook(() => useBaleenPay())
    } catch (e: any) {
      expect(e.message).toContain('BaleenPayProvider')
    }

    spy.mockRestore()
  })
})

// ── Config validation (delegated to SDK) ──

describe('config validation', () => {
  it('throws on missing packageId', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const badConfig = { network: 'testnet' as const, packageId: '', merchantId: '0xm' }

    expect(() => {
      render(
        <BaleenPayProvider config={badConfig}>
          <div />
        </BaleenPayProvider>,
      )
    }).toThrow()

    spy.mockRestore()
  })

  it('throws on missing merchantId', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const badConfig = { network: 'testnet' as const, packageId: '0xp', merchantId: '' }

    expect(() => {
      render(
        <BaleenPayProvider config={badConfig}>
          <div />
        </BaleenPayProvider>,
      )
    }).toThrow()

    spy.mockRestore()
  })
})
