import { useMerchant } from '../hooks/useMerchant.js'
import type { MerchantBadgeProps } from '../types.js'

/**
 * Displays merchant account info.
 *
 * Headless: if `children` render-prop is provided, delegates rendering entirely.
 * Otherwise renders a minimal <div> with brand name, status, and totals.
 */
export function MerchantBadge({
  merchantId,
  className,
  children,
}: MerchantBadgeProps) {
  const { merchant, isLoading, error } = useMerchant(merchantId)

  // Render-prop — full control to consumer
  if (typeof children === 'function') {
    return <>{children(merchant!, isLoading)}</>
  }

  if (isLoading) {
    return (
      <div className={className} data-baleenpay="merchant-badge" data-loading="true">
        <span data-baleenpay="loading">Loading...</span>
      </div>
    )
  }

  if (error) {
    return (
      <div className={className} data-baleenpay="merchant-badge" data-error="true">
        <span data-baleenpay="error" role="alert">{error.message}</span>
      </div>
    )
  }

  if (!merchant) {
    return (
      <div className={className} data-baleenpay="merchant-badge" data-empty="true">
        <span data-baleenpay="empty">No merchant data</span>
      </div>
    )
  }

  return (
    <div
      className={className}
      data-baleenpay="merchant-badge"
      data-paused={merchant.pausedByAdmin || merchant.pausedBySelf || undefined}
    >
      <span data-baleenpay="brand">{merchant.brandName}</span>
      <span data-baleenpay="status">{merchant.pausedByAdmin || merchant.pausedBySelf ? 'Paused' : 'Active'}</span>
      <span data-baleenpay="total">{merchant.totalReceived.toString()}</span>
      <span data-baleenpay="subscriptions">{merchant.activeSubscriptions}</span>
    </div>
  )
}
