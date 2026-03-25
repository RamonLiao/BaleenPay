// packages/sdk/src/version.ts

import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'

export interface VersionInfo {
  hasV2: boolean
}

const cache = new WeakMap<SuiJsonRpcClient, VersionInfo>()

export async function detectVersion(client: SuiJsonRpcClient, packageId: string): Promise<VersionInfo> {
  const cached = cache.get(client)
  if (cached) return cached

  try {
    const mod = await client.getNormalizedMoveModule({
      package: packageId,
      module: 'payment',
    })
    const hasV2 = 'pay_once_v2' in mod.exposedFunctions
    const result: VersionInfo = { hasV2 }
    cache.set(client, result)
    return result
  } catch {
    return { hasV2: false }
  }
}
