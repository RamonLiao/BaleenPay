import { useState, useCallback } from 'react'
import { useDAppKit, useCurrentAccount } from '@mysten/dapp-kit-react'
import { useBaleenPay } from './useBaleenPay.js'
import type {
  SubscribeParams,
  FundParams,
  ObjectId,
  UseSubscriptionReturn,
  MutationStatus,
} from '../types.js'

/**
 * Hook for subscription operations via BaleenPay.
 *
 * Provides subscribe, cancel, fund, and process actions.
 * All share the same status/error/result state — only one action at a time.
 */
export function useSubscription(): UseSubscriptionReturn {
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

  const execute = useCallback(
    async (buildFn: () => Promise<{ tx: import('@mysten/sui/transactions').Transaction }> | { tx: import('@mysten/sui/transactions').Transaction }) => {
      if (!account) {
        setError(new Error('Wallet not connected'))
        setStatus('error')
        return
      }

      try {
        setStatus('building')
        setError(null)
        setResult(null)
        const { tx } = await buildFn()

        setStatus('signing')
        const txResult = await dAppKit.signAndExecuteTransaction({ transaction: tx })

        if (txResult.FailedTransaction) {
          throw new Error(
            txResult.FailedTransaction.status.error?.message ?? 'Transaction failed',
          )
        }

        setStatus('confirming')
        const digest = txResult.Transaction.digest

        setResult(digest)
        setStatus('success')
      } catch (err) {
        const error = err instanceof Error ? err : new Error(String(err))
        const isRejected = error.message.toLowerCase().includes('reject')
          || error.message.toLowerCase().includes('denied')
          || error.message.toLowerCase().includes('cancelled')
        setError(error)
        setStatus(isRejected ? 'rejected' : 'error')
      }
    },
    [account, dAppKit],
  )

  const subscribe = useCallback(
    (params: SubscribeParams) =>
      execute(() => client.subscribe(params, account!.address)),
    [client, account, execute],
  )

  const cancel = useCallback(
    (subscriptionId: ObjectId, coinType: string) =>
      execute(() => client.cancelSubscription(subscriptionId, coinType)),
    [client, execute],
  )

  const fund = useCallback(
    (params: FundParams) =>
      execute(() => client.fundSubscription(params, account!.address)),
    [client, account, execute],
  )

  const process = useCallback(
    (subscriptionId: ObjectId, coinType: string) =>
      execute(() => client.processSubscription(subscriptionId, coinType)),
    [client, execute],
  )

  return { subscribe, cancel, fund, process, status, error, result, reset }
}
