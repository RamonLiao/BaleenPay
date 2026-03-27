import { useCallback, useEffect } from 'react'
import { useSubscription } from '../hooks/useSubscription.js'
import type { SubscribeButtonProps } from '../types.js'

/**
 * One-click subscription button.
 *
 * Same pattern as CheckoutButton — headless with data-status + render-prop children.
 */
export function SubscribeButton({
  amountPerPeriod,
  periodMs,
  prepaidPeriods,
  coin,
  orderId,
  onSuccess,
  onError,
  disabled,
  className,
  children,
}: SubscribeButtonProps) {
  const { subscribe, status, error, result, reset } = useSubscription()

  const isBusy = status === 'building' || status === 'signing' || status === 'confirming'

  useEffect(() => {
    if (status === 'success' && result) onSuccess?.(result)
  }, [status, result, onSuccess])

  useEffect(() => {
    if ((status === 'error' || status === 'rejected') && error) onError?.(error)
  }, [status, error, onError])

  const handleClick = useCallback(() => {
    if (isBusy) return
    if (status !== 'idle') reset()
    subscribe({ amountPerPeriod, periodMs, prepaidPeriods, coin, orderId })
  }, [amountPerPeriod, periodMs, prepaidPeriods, coin, orderId, isBusy, status, reset, subscribe])

  const state = { status, error, result }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={disabled || isBusy}
      className={className}
      data-status={status}
    >
      {typeof children === 'function'
        ? children(state)
        : children ?? defaultLabel(status)}
    </button>
  )
}

function defaultLabel(status: string): string {
  switch (status) {
    case 'building': return 'Preparing...'
    case 'signing': return 'Confirm in wallet...'
    case 'confirming': return 'Confirming...'
    case 'success': return 'Subscribed!'
    case 'error': return 'Failed — Retry'
    case 'rejected': return 'Rejected — Retry'
    default: return 'Subscribe'
  }
}
