import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useFloatSync } from './useFloatSync.js'
import type { ObjectId, UseYieldInfoReturn } from '../types.js'

/**
 * Query hook for merchant yield info.
 *
 * Fetches on-chain yield data (idle principal, accrued yield, vault balance)
 * via the SDK client. Polls every 30 seconds.
 */
export function useYieldInfo(merchantId?: ObjectId): UseYieldInfoReturn {
  const client = useFloatSync()
  const queryClient = useQueryClient()
  const id = merchantId ?? client.config.merchantId

  const { data, isLoading, error } = useQuery({
    queryKey: ['floatsync', 'yield-info', id],
    queryFn: () => client.getYieldInfo(id),
    refetchInterval: 30_000,
  })

  return {
    yieldInfo: data,
    isLoading,
    error: error as Error | null,
    refetch: () => {
      queryClient.invalidateQueries({ queryKey: ['floatsync', 'yield-info', id] })
    },
  }
}
