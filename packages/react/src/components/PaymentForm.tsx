import { useState, useCallback, useEffect, useId } from 'react'
import { usePayment } from '../hooks/usePayment.js'
import type { PaymentFormProps } from '../types.js'

const DEFAULT_COINS = ['SUI', 'USDC']

/**
 * Minimal payment form: amount input + coin selector + pay button.
 *
 * No inline styles — all elements have `data-floatsync-*` attributes for CSS targeting.
 * Generates unique IDs for label/input association (SSR-safe via useId).
 */
export function PaymentForm({
  coins = DEFAULT_COINS,
  defaultCoin,
  orderId: externalOrderId,
  onSuccess,
  onError,
  disabled,
  className,
}: PaymentFormProps) {
  const { pay, status, error, result, reset } = usePayment()
  const formId = useId()

  const [amount, setAmount] = useState('')
  const [coin, setCoin] = useState(defaultCoin ?? coins[0] ?? 'SUI')
  const [orderId, setOrderId] = useState(externalOrderId ?? '')

  // Sync external orderId if provided
  useEffect(() => {
    if (externalOrderId !== undefined) setOrderId(externalOrderId)
  }, [externalOrderId])

  const isBusy = status === 'building' || status === 'signing' || status === 'confirming'

  useEffect(() => {
    if (status === 'success' && result) onSuccess?.(result)
  }, [status, result, onSuccess])

  useEffect(() => {
    if ((status === 'error' || status === 'rejected') && error) onError?.(error)
  }, [status, error, onError])

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault()
      if (isBusy) return

      const parsed = parseFloat(amount)
      if (!amount || isNaN(parsed) || parsed <= 0) return
      if (!orderId.trim()) return

      if (status !== 'idle') reset()
      pay({ amount: BigInt(Math.floor(parsed)), coin, orderId: orderId.trim() })
    },
    [amount, coin, orderId, isBusy, status, reset, pay],
  )

  return (
    <form
      onSubmit={handleSubmit}
      className={className}
      data-floatsync="payment-form"
      data-status={status}
    >
      <div data-floatsync="field">
        <label htmlFor={`${formId}-amount`}>Amount</label>
        <input
          id={`${formId}-amount`}
          type="number"
          min="1"
          step="1"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          disabled={disabled || isBusy}
          placeholder="0"
          data-floatsync="amount-input"
          required
        />
      </div>

      <div data-floatsync="field">
        <label htmlFor={`${formId}-coin`}>Coin</label>
        {coins.length === 1 ? (
          <input
            id={`${formId}-coin`}
            type="text"
            value={coins[0]}
            readOnly
            data-floatsync="coin-input"
          />
        ) : (
          <select
            id={`${formId}-coin`}
            value={coin}
            onChange={(e) => setCoin(e.target.value)}
            disabled={disabled || isBusy}
            data-floatsync="coin-select"
          >
            {coins.map((c) => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
        )}
      </div>

      {externalOrderId === undefined && (
        <div data-floatsync="field">
          <label htmlFor={`${formId}-order`}>Order ID</label>
          <input
            id={`${formId}-order`}
            type="text"
            value={orderId}
            onChange={(e) => setOrderId(e.target.value)}
            disabled={disabled || isBusy}
            placeholder="order-123"
            data-floatsync="order-input"
            required
          />
        </div>
      )}

      <button
        type="submit"
        disabled={disabled || isBusy || !amount || !orderId.trim()}
        data-floatsync="submit"
        data-status={status}
      >
        {statusLabel(status)}
      </button>

      {status === 'error' && error && (
        <p data-floatsync="error" role="alert">{error.message}</p>
      )}
      {status === 'rejected' && (
        <p data-floatsync="rejected" role="alert">Transaction was rejected</p>
      )}
      {status === 'success' && (
        <p data-floatsync="success">Payment confirmed</p>
      )}
    </form>
  )
}

function statusLabel(status: string): string {
  switch (status) {
    case 'building': return 'Preparing...'
    case 'signing': return 'Confirm in wallet...'
    case 'confirming': return 'Confirming...'
    case 'success': return 'Paid!'
    case 'error':
    case 'rejected': return 'Retry'
    default: return 'Pay'
  }
}
