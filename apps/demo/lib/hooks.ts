/**
 * Hook barrel for demo mode.
 * When NEXT_PUBLIC_DEMO_MODE=true, exports mock hooks (no wallet/chain needed).
 * To use real hooks, remove .env.local and import directly from @floatsync/react.
 */
'use client'

export {
  useMockPayment as usePaymentHook,
  useMockSubscription as useSubscriptionHook,
  useMockMerchant as useMerchantHook,
  useMockPaymentHistory as usePaymentHistoryHook,
  useMockYieldInfo as useYieldInfoHook,
  useMockYieldHistory as useYieldHistoryHook,
  useMockClaimYield as useClaimYieldHook,
  useMockCurrentAccount as useCurrentAccountHook,
  useMockDAppKit as useDAppKitHook,
} from './demo-hooks'
