import { useState, useCallback } from 'react'
import { useDAppKit, useCurrentAccount } from '@mysten/dapp-kit-react'
import { useBaleenPay } from './useBaleenPay.js'
import type { UseClaimYieldReturn, MutationStatus } from '../types.js'

/**
 * Mutation hook for claiming accrued yield.
 *
 * State machine: idle → building → signing → confirming → success
 * Error/rejected branches auto-reset is caller's responsibility via reset().
 */
export function useClaimYield(): UseClaimYieldReturn {
  const client = useBaleenPay()
  const dAppKit = useDAppKit()
  const account = useCurrentAccount()

  const [status, setStatus] = useState<MutationStatus>('idle')
  const [error, setError] = useState<Error | null>(null)
  const [txDigest, setTxDigest] = useState<string | null>(null)

  const reset = useCallback(() => {
    setStatus('idle')
    setError(null)
    setTxDigest(null)
  }, [])

  const claim = useCallback(async (merchantCapId: string, coinType: string = 'USDB') => {
    if (!account) {
      setError(new Error('Wallet not connected'))
      setStatus('error')
      return
    }

    try {
      // Build transaction via SDK
      setStatus('building')
      setError(null)
      setTxDigest(null)
      const { tx } = client.claimYield(merchantCapId, coinType)

      // Sign & execute via dapp-kit
      setStatus('signing')
      const txResult = await dAppKit.signAndExecuteTransaction({ transaction: tx })

      if (txResult.FailedTransaction) {
        throw new Error(
          txResult.FailedTransaction.status.error?.message ?? 'Transaction failed',
        )
      }

      // Wait for confirmation
      setStatus('confirming')
      const digest = txResult.Transaction.digest

      setTxDigest(digest)
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

  return { claim, status, error, txDigest, reset }
}
