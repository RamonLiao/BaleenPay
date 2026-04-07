import { useQuery } from '@tanstack/react-query'
import { useBaleenPay } from './useBaleenPay.js'
import type { ObjectId, UseYieldHistoryReturn } from '../types.js'

/**
 * Query hook for yield history data points and claim events.
 *
 * MVP: returns empty arrays. Will be populated when the indexer
 * exposes yield-specific event queries.
 */
export function useYieldHistory(merchantId?: ObjectId): UseYieldHistoryReturn {
  const client = useBaleenPay()
  const id = merchantId ?? client.config.merchantId

  const { data, isLoading, error } = useQuery({
    queryKey: ['baleenpay', 'yield-history', id],
    queryFn: async () => {
      // MVP stub — indexer yield history not yet available.
      // Return empty data so consumers can wire up UI now.
      return { dataPoints: [], claimEvents: [] }
    },
  })

  return {
    dataPoints: data?.dataPoints ?? [],
    claimEvents: data?.claimEvents ?? [],
    isLoading,
    error: error as Error | null,
  }
}
