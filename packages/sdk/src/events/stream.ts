// packages/sdk/src/events/stream.ts

import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'
import type { EventCallback, FloatSyncEventData, FloatSyncEventName, Unsubscribe } from '../types.js'
import { normalizeEvent } from './types.js'

interface ListenerEntry {
  callback: EventCallback
  filter?: Record<string, unknown>
}

const DEFAULT_POLL_INTERVAL_MS = 3000

export class EventStream {
  private packageId: string
  private listeners: Map<string, Set<ListenerEntry>> = new Map()
  private pollTimer?: ReturnType<typeof setInterval>
  private cursor?: { txDigest: string; eventSeq: string }

  constructor(packageId: string) {
    this.packageId = packageId
  }

  on(
    event: FloatSyncEventName,
    callback: EventCallback,
    filter?: Record<string, unknown>,
  ): Unsubscribe {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set())
    }

    const entry: ListenerEntry = { callback, filter }
    this.listeners.get(event)!.add(entry)

    return () => {
      this.listeners.get(event)?.delete(entry)
    }
  }

  /**
   * Start polling for on-chain events.
   * Uses queryEvents with cursor tracking (subscribeEvent removed in @mysten/sui v2).
   */
  async start(client: SuiJsonRpcClient, intervalMs = DEFAULT_POLL_INTERVAL_MS): Promise<void> {
    // Seed cursor from latest event so we only see new events
    const seed = await client.queryEvents({
      query: { MoveEventModule: { package: this.packageId, module: 'events' } },
      limit: 1,
      order: 'descending',
    })
    if (seed.data.length > 0) {
      this.cursor = { txDigest: seed.data[0].id.txDigest, eventSeq: seed.data[0].id.eventSeq }
    }

    this.pollTimer = setInterval(async () => {
      try {
        const result = await client.queryEvents({
          query: { MoveEventModule: { package: this.packageId, module: 'events' } },
          cursor: this.cursor ?? undefined,
          limit: 50,
          order: 'ascending',
        })

        for (const evt of result.data) {
          const data = normalizeEvent(evt.type, evt.parsedJson as Record<string, unknown>)
          this.dispatch(data)
          this.cursor = { txDigest: evt.id.txDigest, eventSeq: evt.id.eventSeq }
        }
      } catch {
        // Silently skip poll errors — next interval will retry
      }
    }, intervalMs)
  }

  stop(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = undefined
    }
  }

  /** Dispatch an event to matching listeners. Exposed for testing. */
  dispatch(event: FloatSyncEventData): void {
    const dispatch = (entries: Set<ListenerEntry> | undefined) => {
      if (!entries) return
      for (const entry of entries) {
        if (entry.filter && !this.matchesFilter(event, entry.filter)) continue
        entry.callback(event)
      }
    }

    // Exact event name listeners
    dispatch(this.listeners.get(event.type))
    // Wildcard listeners
    dispatch(this.listeners.get('*'))
  }

  private matchesFilter(event: FloatSyncEventData, filter: Record<string, unknown>): boolean {
    for (const [key, value] of Object.entries(filter)) {
      if (event[key] !== value) return false
    }
    return true
  }
}
