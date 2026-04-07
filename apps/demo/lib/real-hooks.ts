/**
 * Real-chain hooks: thin re-exports from @baleenpay/react + @mysten/dapp-kit-react.
 * Same export names as demo-hooks.ts so pages don't need to change.
 */
'use client'

export {
  usePayment as usePaymentHook,
  useSubscription as useSubscriptionHook,
  useMerchant as useMerchantHook,
  usePaymentHistory as usePaymentHistoryHook,
  useYieldInfo as useYieldInfoHook,
  useYieldHistory as useYieldHistoryHook,
  useClaimYield as useClaimYieldHook,
} from '@baleenpay/react'

export { useCurrentAccount as useCurrentAccountHook } from '@mysten/dapp-kit-react'
export { useDAppKit as useDAppKitHook } from '@mysten/dapp-kit-react'
