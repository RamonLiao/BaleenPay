// packages/sdk/src/events/stream.ts

import type { SuiGraphQLClient } from '@mysten/sui/graphql'
import type { EventCallback, FloatSyncEventData, FloatSyncEventName, Unsubscribe } from '../types.js'
import { normalizeEvent } from './types.js'
import { QUERY_EVENTS } from './queries.js'
import type { QueryEventsResult } from './queries.js'

interface ListenerEntry {
  callback: EventCallback
  filter?: Record<string, unknown>
}

const DEFAULT_POLL_INTERVAL_MS = 3000

export class EventStream {
  private packageId: string
  private listeners: Map<string, Set<ListenerEntry>> = new Map()
  private pollTimer?: ReturnType<typeof setInterval>
  private cursor?: string | null

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
   * Start polling for on-chain events via GraphQL.
   * Uses cursor tracking to only receive new events.
   */
  async start(client: SuiGraphQLClient, intervalMs = DEFAULT_POLL_INTERVAL_MS): Promise<void> {
    // Seed cursor from latest event so we only see new events
    const eventType = `${this.packageId}::events`
    const seed = await client.query<QueryEventsResult>({
      query: QUERY_EVENTS,
      variables: { type: eventType, first: 1 },
    })
    if (seed.data?.events.nodes.length) {
      this.cursor = seed.data.events.pageInfo.endCursor
    }

    this.pollTimer = setInterval(async () => {
      try {
        const result = await client.query<QueryEventsResult>({
          query: QUERY_EVENTS,
          variables: {
            type: eventType,
            after: this.cursor ?? undefined,
            first: 50,
          },
        })

        if (!result.data) return

        for (const node of result.data.events.nodes) {
          if (!node.type?.repr || !node.contents?.json) continue
          const data = normalizeEvent(node.type.repr, node.contents.json)
          this.dispatch(data)
        }

        if (result.data.events.pageInfo.endCursor) {
          this.cursor = result.data.events.pageInfo.endCursor
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
