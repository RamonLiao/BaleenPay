import { useState, useCallback } from 'react'
import { useDAppKit, useCurrentAccount } from '@mysten/dapp-kit-react'
import { useBaleenPay } from './useBaleenPay.js'
import type { PayParams, UsePaymentReturn, MutationStatus } from '../types.js'

/**
 * Hook for one-time payments via BaleenPay.
 *
 * State machine: idle → building → signing → confirming → success
 * Error/rejected branches auto-reset is caller's responsibility via reset().
 */
export function usePayment(): UsePaymentReturn {
  const client = useBaleenPay()
  const dAppKit = useDAppKit()
  const account = useCurrentAccount()

  const [status, setStatus] = useState<MutationStatus>('idle')
  const [error, setError] = useState<Error | null>(null)
  const [result, setResult] = useState<string | null>(null)

  const reset = useCallback(() => {
    setStatus('idle')
    setError(null)
    setResult(null)
  }, [])

  const pay = useCallback(async (params: PayParams) => {
    if (!account) {
      setError(new Error('Wallet not connected'))
      setStatus('error')
      return
    }

    try {
      // Build transaction via SDK
      setStatus('building')
      setError(null)
      setResult(null)
      const { tx } = await client.pay(params, account.address)

      // Sign & execute via dapp-kit
      setStatus('signing')
      const txResult = await dAppKit.signAndExecuteTransaction({ transaction: tx })

      if (txResult.FailedTransaction) {
        throw new Error(
          txResult.FailedTransaction.status.error?.message ?? 'Transaction failed',
        )
      }

      // Wait for indexer via SDK's own SuiClient
      setStatus('confirming')
      const digest = txResult.Transaction.digest

      setResult(digest)
      setStatus('success')
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err))
      // Detect wallet rejection (common wallet error patterns)
      const isRejected = error.message.toLowerCase().includes('reject')
        || error.message.toLowerCase().includes('denied')
        || error.message.toLowerCase().includes('cancelled')
      setError(error)
      setStatus(isRejected ? 'rejected' : 'error')
    }
  }, [account, client, dAppKit])

  return { pay, status, error, result, reset }
}
