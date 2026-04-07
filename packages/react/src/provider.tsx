import { createContext, useMemo } from 'react'
import { BaleenPay } from '@baleenpay/sdk'
import type { BaleenPayProviderProps } from './types.js'

export const BaleenPayContext = createContext<BaleenPay | null>(null)

export function BaleenPayProvider({ config, options, children }: BaleenPayProviderProps) {
  const client = useMemo(
    () => new BaleenPay(config, options),
    // Stable key: re-create only when identity-affecting config changes
    [config.packageId, config.merchantId, config.network, config.grpcUrl, config.graphqlUrl, options?.pendingTtlMs],
  )

  return (
    <BaleenPayContext.Provider value={client}>
      {children}
    </BaleenPayContext.Provider>
  )
}
