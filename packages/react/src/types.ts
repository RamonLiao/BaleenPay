import type { FloatSyncConfig, FloatSyncClientOptions } from '@floatsync/sdk'

export interface FloatSyncProviderProps {
  config: FloatSyncConfig
  options?: FloatSyncClientOptions
  children: React.ReactNode
}

export type { FloatSyncConfig, FloatSyncClientOptions }
