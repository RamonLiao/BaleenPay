// Provider
export { FloatSyncProvider, FloatSyncContext } from './provider.js'

// Hooks
export { useFloatSync } from './hooks/useFloatSync.js'
export { usePayment } from './hooks/usePayment.js'
export { useSubscription } from './hooks/useSubscription.js'
export { useMerchant } from './hooks/useMerchant.js'
export { usePaymentHistory } from './hooks/usePaymentHistory.js'

// Types
export type {
  FloatSyncProviderProps,
  FloatSyncConfig,
  FloatSyncClientOptions,
  MutationStatus,
  MutationState,
  UsePaymentReturn,
  UseSubscriptionReturn,
  UseMerchantReturn,
  UsePaymentHistoryOptions,
  UsePaymentHistoryReturn,
} from './types.js'
