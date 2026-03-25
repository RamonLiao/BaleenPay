// packages/sdk/src/idempotency.ts

import type { ExecutedResult } from './types.js'

export type IdempotencyStatus = 'pending' | ExecutedResult

/**
 * In-memory idempotency guard.
 * Prevents duplicate transaction submissions at the SDK layer,
 * complementing the on-chain OrderKey dedup in the contract.
 */
export class IdempotencyGuard {
  private store: Map<string, IdempotencyStatus> = new Map()

  /** Default TTL for pending entries (ms). Prevents stale locks. */
  private pendingTimestamps: Map<string, number> = new Map()
  private readonly pendingTtlMs: number

  constructor(opts?: { pendingTtlMs?: number }) {
    this.pendingTtlMs = opts?.pendingTtlMs ?? 60_000 // 1 minute default
  }

  /**
   * Generate idempotency key.
   * - If orderId is provided: deterministic key from (merchantId, orderId)
   * - Otherwise: fingerprint from (merchantId, method, amount, coin, time-bucket)
   */
  static key(
    merchantId: string,
    orderId?: string,
    fallback?: { method: string; amount: bigint; coin: string; bucketMs?: number },
  ): string {
    if (orderId) {
      return `${merchantId}:${orderId}`
    }
    if (fallback) {
      const bucket = Math.floor(Date.now() / (fallback.bucketMs ?? 5_000))
      return `${merchantId}:${fallback.method}:${fallback.amount}:${fallback.coin}:${bucket}`
    }
    throw new Error('IdempotencyGuard.key requires orderId or fallback params')
  }

  /**
   * Check if a key has been seen.
   * Returns undefined if not seen, 'pending' if in-flight, or the cached result.
   * Auto-evicts stale pending entries.
   */
  check(key: string): IdempotencyStatus | undefined {
    const entry = this.store.get(key)
    if (entry === 'pending') {
      const ts = this.pendingTimestamps.get(key)
      if (ts && Date.now() - ts > this.pendingTtlMs) {
        // Stale pending — evict
        this.store.delete(key)
        this.pendingTimestamps.delete(key)
        return undefined
      }
    }
    return entry
  }

  /** Mark a key as pending (in-flight). */
  markPending(key: string): void {
    this.store.set(key, 'pending')
    this.pendingTimestamps.set(key, Date.now())
  }

  /** Mark a key as completed with a result. */
  markCompleted(key: string, result: ExecutedResult): void {
    this.store.set(key, result)
    this.pendingTimestamps.delete(key)
  }

  /** Get the cached result for a completed key. Returns undefined if not completed. */
  getCachedResult(key: string): ExecutedResult | undefined {
    const entry = this.store.get(key)
    if (entry && entry !== 'pending') return entry
    return undefined
  }

  /** Remove a specific key. */
  remove(key: string): void {
    this.store.delete(key)
    this.pendingTimestamps.delete(key)
  }

  /** Clear all entries. */
  reset(): void {
    this.store.clear()
    this.pendingTimestamps.clear()
  }

  /** Number of tracked entries. */
  get size(): number {
    return this.store.size
  }
}
