import { useContext } from 'react'
import { FloatSyncContext } from '../provider.js'
import type { FloatSync } from '@floatsync/sdk'

/**
 * Returns the FloatSync SDK client from the nearest FloatSyncProvider.
 * Throws if called outside a provider.
 */
export function useFloatSync(): FloatSync {
  const client = useContext(FloatSyncContext)
  if (!client) {
    throw new Error(
      'useFloatSync must be used within a <FloatSyncProvider>. ' +
      'Wrap your component tree with <FloatSyncProvider config={...}>.',
    )
  }
  return client
}
