import { useState, useCallback } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useFloatSync } from './useFloatSync.js'
import type { FloatSyncEventData, UsePaymentHistoryOptions, UsePaymentHistoryReturn } from '../types.js'

/**
 * Query hook for payment history via on-chain events.
 *
 * Supports pagination (cursor-based) and payer filtering.
 */
export function usePaymentHistory(options?: UsePaymentHistoryOptions): UsePaymentHistoryReturn {
  const client = useFloatSync()
  const queryClient = useQueryClient()
  const { limit = 20, order = 'desc', payer, enabled = true } = options ?? {}

  const [cursor, setCursor] = useState<string | undefined>(undefined)
  const [allEvents, setAllEvents] = useState<FloatSyncEventData[]>([])

  const { data, isLoading, error } = useQuery({
    queryKey: ['floatsync', 'paymentHistory', client.config.merchantId, { cursor, limit, order, payer }],
    queryFn: () => client.getPaymentHistory({ cursor, limit, order, payer }),
    enabled,
  })

  // Accumulate events from paginated fetches
  const events = cursor ? allEvents : (data?.events ?? [])
  const hasNextPage = data?.hasNextPage ?? false

  const fetchNextPage = useCallback(() => {
    if (data?.nextCursor) {
      setAllEvents((prev) => [...prev, ...(data.events ?? [])])
      setCursor(data.nextCursor)
    }
  }, [data])

  const refetch = useCallback(() => {
    setCursor(undefined)
    setAllEvents([])
    queryClient.invalidateQueries({ queryKey: ['floatsync', 'paymentHistory', client.config.merchantId] })
  }, [client.config.merchantId, queryClient])

  return {
    events,
    isLoading,
    error: error as Error | null,
    hasNextPage,
    fetchNextPage,
    refetch,
  }
}
