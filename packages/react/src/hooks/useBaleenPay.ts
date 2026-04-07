import { useContext } from 'react'
import { BaleenPayContext } from '../provider.js'
import type { BaleenPay } from '@baleenpay/sdk'

/**
 * Returns the BaleenPay SDK client from the nearest BaleenPayProvider.
 * Throws if called outside a provider.
 */
export function useBaleenPay(): BaleenPay {
  const client = useContext(BaleenPayContext)
  if (!client) {
    throw new Error(
      'useBaleenPay must be used within a <BaleenPayProvider>. ' +
      'Wrap your component tree with <BaleenPayProvider config={...}>.',
    )
  }
  return client
}
