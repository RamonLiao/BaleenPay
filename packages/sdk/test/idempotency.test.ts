import { describe, it, expect, beforeEach, vi } from 'vitest'
import { IdempotencyGuard } from '../src/idempotency.js'
import type { ExecutedResult } from '../src/types.js'

const mockResult: ExecutedResult = {
  digest: '0xabc123',
  status: 'success',
  events: [],
  gasUsed: 1000n,
  payment: { orderId: 'order-1', amount: 500n, coinType: '0x2::sui::SUI' },
}

describe('IdempotencyGuard', () => {
  let guard: IdempotencyGuard

  beforeEach(() => {
    guard = new IdempotencyGuard()
  })

  describe('key generation', () => {
    it('generates deterministic key from merchantId + orderId', () => {
      const key = IdempotencyGuard.key('0xmerchant', 'order-123')
      expect(key).toBe('0xmerchant:order-123')
    })

    it('generates same key for same inputs', () => {
      const a = IdempotencyGuard.key('0xm', 'o1')
      const b = IdempotencyGuard.key('0xm', 'o1')
      expect(a).toBe(b)
    })

    it('generates different keys for different orderIds', () => {
      const a = IdempotencyGuard.key('0xm', 'o1')
      const b = IdempotencyGuard.key('0xm', 'o2')
      expect(a).not.toBe(b)
    })

    it('generates fallback key with time bucket', () => {
      const key = IdempotencyGuard.key('0xm', undefined, {
        method: 'pay',
        amount: 100n,
        coin: 'USDC',
        bucketMs: 5000,
      })
      expect(key).toContain('0xm:pay:100:USDC:')
    })

    it('same time bucket → same fallback key', () => {
      const opts = { method: 'pay', amount: 100n, coin: 'USDC', bucketMs: 60_000 }
      const a = IdempotencyGuard.key('0xm', undefined, opts)
      const b = IdempotencyGuard.key('0xm', undefined, opts)
      expect(a).toBe(b)
    })

    it('throws without orderId or fallback', () => {
      expect(() => IdempotencyGuard.key('0xm')).toThrow('requires orderId or fallback')
    })
  })

  describe('check / markPending / markCompleted', () => {
    it('returns undefined for unseen key', () => {
      expect(guard.check('unknown')).toBeUndefined()
    })

    it('returns pending after markPending', () => {
      guard.markPending('k1')
      expect(guard.check('k1')).toBe('pending')
    })

    it('returns result after markCompleted', () => {
      guard.markPending('k1')
      guard.markCompleted('k1', mockResult)
      expect(guard.check('k1')).toEqual(mockResult)
    })

    it('markCompleted without markPending works', () => {
      guard.markCompleted('k1', mockResult)
      expect(guard.check('k1')).toEqual(mockResult)
    })
  })

  describe('getCachedResult', () => {
    it('returns undefined for unseen key', () => {
      expect(guard.getCachedResult('unknown')).toBeUndefined()
    })

    it('returns undefined for pending key', () => {
      guard.markPending('k1')
      expect(guard.getCachedResult('k1')).toBeUndefined()
    })

    it('returns result for completed key', () => {
      guard.markCompleted('k1', mockResult)
      expect(guard.getCachedResult('k1')).toEqual(mockResult)
    })
  })

  describe('remove', () => {
    it('removes a pending entry', () => {
      guard.markPending('k1')
      guard.remove('k1')
      expect(guard.check('k1')).toBeUndefined()
    })

    it('removes a completed entry', () => {
      guard.markCompleted('k1', mockResult)
      guard.remove('k1')
      expect(guard.check('k1')).toBeUndefined()
    })
  })

  describe('reset', () => {
    it('clears all entries', () => {
      guard.markPending('k1')
      guard.markCompleted('k2', mockResult)
      guard.reset()
      expect(guard.size).toBe(0)
      expect(guard.check('k1')).toBeUndefined()
      expect(guard.check('k2')).toBeUndefined()
    })
  })

  describe('size', () => {
    it('tracks entry count', () => {
      expect(guard.size).toBe(0)
      guard.markPending('k1')
      expect(guard.size).toBe(1)
      guard.markCompleted('k2', mockResult)
      expect(guard.size).toBe(2)
    })
  })

  describe('pending TTL eviction', () => {
    it('evicts stale pending entries', () => {
      const shortGuard = new IdempotencyGuard({ pendingTtlMs: 50 })
      shortGuard.markPending('k1')
      expect(shortGuard.check('k1')).toBe('pending')

      // Simulate time passage
      vi.useFakeTimers()
      vi.advanceTimersByTime(100)
      expect(shortGuard.check('k1')).toBeUndefined()
      vi.useRealTimers()
    })

    it('does not evict completed entries', () => {
      const shortGuard = new IdempotencyGuard({ pendingTtlMs: 50 })
      shortGuard.markCompleted('k1', mockResult)

      vi.useFakeTimers()
      vi.advanceTimersByTime(100)
      expect(shortGuard.check('k1')).toEqual(mockResult)
      vi.useRealTimers()
    })
  })
})
