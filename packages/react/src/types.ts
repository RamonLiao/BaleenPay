import type {
  FloatSyncConfig,
  FloatSyncClientOptions,
  PayParams,
  SubscribeParams,
  FundParams,
  MerchantInfo,
  SubscriptionInfo,
  FloatSyncEventData,
  ObjectId,
} from '@floatsync/sdk'

export interface FloatSyncProviderProps {
  config: FloatSyncConfig
  options?: FloatSyncClientOptions
  children: React.ReactNode
}

// ── Mutation status ──

export type MutationStatus =
  | 'idle'
  | 'building'
  | 'signing'
  | 'confirming'
  | 'success'
  | 'error'
  | 'rejected'

export interface MutationState<TResult = string> {
  status: MutationStatus
  error: Error | null
  /** Transaction digest on success */
  result: TResult | null
}

// ── usePayment ──

export interface UsePaymentReturn {
  pay: (params: PayParams) => Promise<void>
  status: MutationStatus
  error: Error | null
  /** Transaction digest */
  result: string | null
  reset: () => void
}

// ── useSubscription ──

export interface UseSubscriptionReturn {
  subscribe: (params: SubscribeParams) => Promise<void>
  cancel: (subscriptionId: ObjectId, coinType: string) => Promise<void>
  fund: (params: FundParams) => Promise<void>
  process: (subscriptionId: ObjectId, coinType: string) => Promise<void>
  status: MutationStatus
  error: Error | null
  result: string | null
  reset: () => void
}

// ── useMerchant ──

export interface UseMerchantReturn {
  merchant: MerchantInfo | undefined
  isLoading: boolean
  error: Error | null
  refetch: () => void
}

// ── usePaymentHistory ──

export interface UsePaymentHistoryOptions {
  /** Number of events per page. Default: 20 */
  limit?: number
  order?: 'asc' | 'desc'
  /** Filter by payer address */
  payer?: string
  /** Auto-fetch on mount. Default: true */
  enabled?: boolean
}

export interface UsePaymentHistoryReturn {
  events: FloatSyncEventData[]
  isLoading: boolean
  error: Error | null
  hasNextPage: boolean
  fetchNextPage: () => void
  refetch: () => void
}

export type {
  FloatSyncConfig,
  FloatSyncClientOptions,
  PayParams,
  SubscribeParams,
  FundParams,
  MerchantInfo,
  SubscriptionInfo,
  FloatSyncEventData,
  ObjectId,
}
