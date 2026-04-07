/**
 * Hook barrel.
 * When NEXT_PUBLIC_DEMO_MODE=true → swap this to re-export from './demo-hooks'.
 * When NEXT_PUBLIC_DEMO_MODE=false (default) → real chain hooks.
 */
'use client'

export {
  usePaymentHook,
  useSubscriptionHook,
  useMerchantHook,
  usePaymentHistoryHook,
  useYieldInfoHook,
  useYieldHistoryHook,
  useClaimYieldHook,
  useCurrentAccountHook,
  useDAppKitHook,
} from './real-hooks'
