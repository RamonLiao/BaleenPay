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
      <div className={className} data-floatsync="merchant-badge" data-loading="true">
        <span data-floatsync="loading">Loading...</span>
      </div>
    )
  }

  if (error) {
    return (
      <div className={className} data-floatsync="merchant-badge" data-error="true">
        <span data-floatsync="error" role="alert">{error.message}</span>
      </div>
    )
  }

  if (!merchant) {
    return (
      <div className={className} data-floatsync="merchant-badge" data-empty="true">
        <span data-floatsync="empty">No merchant data</span>
      </div>
    )
  }

  return (
    <div
      className={className}
      data-floatsync="merchant-badge"
      data-paused={merchant.paused || undefined}
    >
      <span data-floatsync="brand">{merchant.brandName}</span>
      <span data-floatsync="status">{merchant.paused ? 'Paused' : 'Active'}</span>
      <span data-floatsync="total">{merchant.totalReceived.toString()}</span>
      <span data-floatsync="subscriptions">{merchant.activeSubscriptions}</span>
    </div>
  )
}
