import { describe, it, expect, vi } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { render, screen } from '@testing-library/react'
import { FloatSyncProvider, useFloatSync, FloatSyncContext } from '../src/index.js'
import { FloatSync } from '@floatsync/sdk'
import type { ReactNode } from 'react'

// ── Mock SuiJsonRpcClient so FloatSync constructor works ──
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
    <FloatSyncProvider config={testConfig}>
      {children}
    </FloatSyncProvider>
  )
}

// ── Provider rendering ──

describe('FloatSyncProvider', () => {
  it('renders children', () => {
    render(
      <FloatSyncProvider config={testConfig}>
        <div data-testid="child">hello</div>
      </FloatSyncProvider>,
    )
    expect(screen.getByTestId('child')).toBeDefined()
    expect(screen.getByTestId('child').textContent).toBe('hello')
  })

  it('provides a FloatSync client via context', () => {
    const { result } = renderHook(() => useFloatSync(), { wrapper })
    expect(result.current).toBeInstanceOf(FloatSync)
  })

  it('client has correct config', () => {
    const { result } = renderHook(() => useFloatSync(), { wrapper })
    expect(result.current.config.network).toBe('testnet')
    expect(result.current.config.packageId).toBe('0xpkg123')
    expect(result.current.config.merchantId).toBe('0xmerchant456')
  })

  it('returns stable client reference on re-render with same config', () => {
    const refs: FloatSync[] = []
    const { rerender } = renderHook(() => {
      const client = useFloatSync()
      refs.push(client)
      return client
    }, { wrapper })

    rerender()
    expect(refs.length).toBe(2)
    expect(refs[0]).toBe(refs[1]) // same reference = useMemo working
  })

  it('creates new client when packageId changes', () => {
    const refs: FloatSync[] = []
    let cfg = { ...testConfig }

    function DynamicWrapper({ children }: { children: ReactNode }) {
      return (
        <FloatSyncProvider config={cfg}>
          {children}
        </FloatSyncProvider>
      )
    }

    const { rerender } = renderHook(() => {
      const client = useFloatSync()
      refs.push(client)
      return client
    }, { wrapper: DynamicWrapper })

    cfg = { ...testConfig, packageId: '0xnewpkg' }
    rerender()

    expect(refs.length).toBe(2)
    expect(refs[0]).not.toBe(refs[1])
    expect(refs[1].config.packageId).toBe('0xnewpkg')
  })

  it('passes options to FloatSync client', () => {
    function WrapperWithOptions({ children }: { children: ReactNode }) {
      return (
        <FloatSyncProvider config={testConfig} options={{ pendingTtlMs: 30000 }}>
          {children}
        </FloatSyncProvider>
      )
    }

    const { result } = renderHook(() => useFloatSync(), { wrapper: WrapperWithOptions })
    // Client was created successfully with options — no throw
    expect(result.current).toBeInstanceOf(FloatSync)
  })
})

// ── useFloatSync ──

describe('useFloatSync', () => {
  it('throws when used outside provider', () => {
    // Suppress React error boundary console noise
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})

    expect(() => {
      renderHook(() => useFloatSync())
    }).toThrow('useFloatSync must be used within a <FloatSyncProvider>')

    spy.mockRestore()
  })

  it('error message mentions FloatSyncProvider', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})

    try {
      renderHook(() => useFloatSync())
    } catch (e: any) {
      expect(e.message).toContain('FloatSyncProvider')
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
        <FloatSyncProvider config={badConfig}>
          <div />
        </FloatSyncProvider>,
      )
    }).toThrow()

    spy.mockRestore()
  })

  it('throws on missing merchantId', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const badConfig = { network: 'testnet' as const, packageId: '0xp', merchantId: '' }

    expect(() => {
      render(
        <FloatSyncProvider config={badConfig}>
          <div />
        </FloatSyncProvider>,
      )
    }).toThrow()

    spy.mockRestore()
  })
})
