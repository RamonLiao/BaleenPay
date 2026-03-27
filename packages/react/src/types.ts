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
  YieldInfo,
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

// ── useYieldInfo ──

export interface UseYieldInfoReturn {
  yieldInfo: YieldInfo | undefined
  isLoading: boolean
  error: Error | null
  refetch: () => void
}

// ── useYieldHistory ──

export interface YieldDataPoint {
  timestamp: number
  cumulativeYield: number
  apy: number
}

export interface ClaimEvent {
  timestamp: number
  amount: bigint
  txDigest: string
}

export interface UseYieldHistoryReturn {
  dataPoints: YieldDataPoint[]
  claimEvents: ClaimEvent[]
  isLoading: boolean
  error: Error | null
}

// ── useClaimYield ──

export interface UseClaimYieldReturn {
  claim: (merchantCapId: string) => Promise<void>
  status: MutationStatus
  error: Error | null
  txDigest: string | null
  reset: () => void
}

// ── Component props ──

export interface CheckoutButtonProps {
  amount: bigint | number
  coin: string
  orderId: string
  onSuccess?: (digest: string) => void
  onError?: (error: Error) => void
  disabled?: boolean
  className?: string
  children?: React.ReactNode | ((state: MutationState) => React.ReactNode)
}

export interface PaymentFormProps {
  coins?: string[]
  defaultCoin?: string
  orderId?: string
  onSuccess?: (digest: string) => void
  onError?: (error: Error) => void
  disabled?: boolean
  className?: string
}

export interface SubscribeButtonProps {
  amountPerPeriod: bigint | number
  periodMs: number
  prepaidPeriods: number
  coin: string
  orderId: string
  onSuccess?: (digest: string) => void
  onError?: (error: Error) => void
  disabled?: boolean
  className?: string
  children?: React.ReactNode | ((state: MutationState) => React.ReactNode)
}

export interface MerchantBadgeProps {
  merchantId?: ObjectId
  className?: string
  children?: (info: MerchantInfo, isLoading: boolean) => React.ReactNode
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
  YieldInfo,
}
