/**
 * Demo-mode hooks: drop-in replacements for @baleenpay/react hooks.
 * Use mock data + simulated tx flows. No wallet or chain needed.
 */
'use client'

import { useState, useCallback } from 'react'
import type { MutationStatus } from '@baleenpay/react'
import {
  MOCK_MERCHANT,
  MOCK_YIELD_INFO,
  MOCK_YIELD_DATA_POINTS,
  MOCK_PAYMENT_EVENTS,
  MOCK_CLAIM_EVENTS,
  MOCK_ACCOUNT,
  simulateTx,
} from './mock-data'

// ── Query hooks ──

export function useMockMerchant() {
  return {
    merchant: MOCK_MERCHANT,
    isLoading: false,
    error: null,
    refetch: () => {},
  }
}

export function useMockPaymentHistory() {
  return {
    events: MOCK_PAYMENT_EVENTS,
    isLoading: false,
    error: null,
    hasNextPage: false,
    fetchNextPage: () => {},
    refetch: () => {},
  }
}

export function useMockYieldInfo() {
  return {
    yieldInfo: MOCK_YIELD_INFO,
    isLoading: false,
    error: null,
    refetch: () => {},
  }
}

export function useMockYieldHistory() {
  return {
    dataPoints: MOCK_YIELD_DATA_POINTS,
    claimEvents: MOCK_CLAIM_EVENTS,
    isLoading: false,
    error: null,
  }
}

// ── Mutation hooks ──

function useMockMutation() {
  const [status, setStatus] = useState<MutationStatus>('idle')
  const [error, setError] = useState<Error | null>(null)
  const [result, setResult] = useState<string | null>(null)

  const reset = useCallback(() => {
    setStatus('idle')
    setError(null)
    setResult(null)
  }, [])

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const execute = useCallback(async (_opts?: any) => {
    try {
      setStatus('building')
      setError(null)
      setResult(null)
      // Simulate short delays for each stage
      await new Promise((r) => setTimeout(r, 400))
      setStatus('signing')
      await new Promise((r) => setTimeout(r, 600))
      setStatus('confirming')
      await new Promise((r) => setTimeout(r, 500))
      const digest = await simulateTx()
      setResult(digest)
      setStatus('success')
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)))
      setStatus('error')
    }
  }, [])

  return { status, error, result, reset, execute }
}

export function useMockPayment() {
  const { status, error, result, reset, execute } = useMockMutation()
  return {
    pay: execute,
    status,
    error,
    result,
    reset,
  }
}

export function useMockSubscription() {
  const { status, error, result, reset, execute } = useMockMutation()
  return {
    subscribe: execute,
    cancel: execute,
    fund: execute,
    process: execute,
    status,
    error,
    result,
    reset,
  }
}

export function useMockClaimYield() {
  const { status, error, result, reset, execute } = useMockMutation()
  return {
    claim: execute,
    status,
    error,
    txDigest: result,
    reset,
  }
}

// ── DAppKit replacements ──

export function useMockCurrentAccount() {
  return MOCK_ACCOUNT
}

export function useMockDAppKit() {
  return {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    signAndExecuteTransaction: async (_opts?: any) => ({
      Transaction: { digest: '0xmock_digest' },
      FailedTransaction: null as any,
    }),
  }
}
