// packages/sdk/src/version.ts

import type { SuiGrpcClient } from '@mysten/sui/grpc'

export interface VersionInfo {
  hasV2: boolean
}

const cache = new WeakMap<SuiGrpcClient, VersionInfo>()

export async function detectVersion(client: SuiGrpcClient, packageId: string): Promise<VersionInfo> {
  const cached = cache.get(client)
  if (cached) return cached

  try {
    await client.getMoveFunction({
      packageId,
      moduleName: 'payment',
      name: 'pay_once_v2',
    })
    const result: VersionInfo = { hasV2: true }
    cache.set(client, result)
    return result
  } catch {
    const result: VersionInfo = { hasV2: false }
    cache.set(client, result)
    return result
  }
}
