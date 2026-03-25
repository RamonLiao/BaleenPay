import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useFloatSync } from './useFloatSync.js'
import type { ObjectId, UseMerchantReturn } from '../types.js'

/**
 * Query hook for merchant account info.
 *
 * Fetches on-chain MerchantAccount data via the SDK client.
 * Uses the merchantId from config by default.
 */
export function useMerchant(merchantId?: ObjectId): UseMerchantReturn {
  const client = useFloatSync()
  const queryClient = useQueryClient()
  const id = merchantId ?? client.config.merchantId

  const { data, isLoading, error } = useQuery({
    queryKey: ['floatsync', 'merchant', id],
    queryFn: () => client.getMerchant(id),
  })

  return {
    merchant: data,
    isLoading,
    error: error as Error | null,
    refetch: () => {
      queryClient.invalidateQueries({ queryKey: ['floatsync', 'merchant', id] })
    },
  }
}
