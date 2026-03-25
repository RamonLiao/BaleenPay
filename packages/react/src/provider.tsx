import { createContext, useMemo } from 'react'
import { FloatSync } from '@floatsync/sdk'
import type { FloatSyncProviderProps } from './types.js'

export const FloatSyncContext = createContext<FloatSync | null>(null)

export function FloatSyncProvider({ config, options, children }: FloatSyncProviderProps) {
  const client = useMemo(
    () => new FloatSync(config, options),
    // Stable key: re-create only when identity-affecting config changes
    [config.packageId, config.merchantId, config.network, config.rpcUrl, options?.pendingTtlMs],
  )

  return (
    <FloatSyncContext.Provider value={client}>
      {children}
    </FloatSyncContext.Provider>
  )
}
