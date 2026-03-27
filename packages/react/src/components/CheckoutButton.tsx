import { useCallback, useEffect } from 'react'
import { usePayment } from '../hooks/usePayment.js'
import type { CheckoutButtonProps } from '../types.js'

/**
 * One-click payment button.
 *
 * Headless by default — renders a <button> with `data-status` for CSS styling.
 * Accepts render-prop children for custom UI: `children={(state) => ...}`
 */
export function CheckoutButton({
  amount,
  coin,
  orderId,
  onSuccess,
  onError,
  disabled,
  className,
  children,
}: CheckoutButtonProps) {
  const { pay, status, error, result, reset } = usePayment()

  const isBusy = status === 'building' || status === 'signing' || status === 'confirming'

  // Fire callbacks on terminal states
  useEffect(() => {
    if (status === 'success' && result) {
      onSuccess?.(result)
    }
  }, [status, result, onSuccess])

  useEffect(() => {
    if ((status === 'error' || status === 'rejected') && error) {
      onError?.(error)
    }
  }, [status, error, onError])

  const handleClick = useCallback(() => {
    if (isBusy) return
    // Reset if in terminal state, then pay
    if (status !== 'idle') reset()
    pay({ amount, coin, orderId })
  }, [amount, coin, orderId, isBusy, status, reset, pay])

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
    case 'success': return 'Paid!'
    case 'error': return 'Failed — Retry'
    case 'rejected': return 'Rejected — Retry'
    default: return 'Pay'
  }
}
