import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'

/**
 * Validate that a coin type exists on-chain by checking CoinMetadata.
 * Returns decimals if found, throws if not.
 */
export async function validateCoinType(
  client: SuiJsonRpcClient,
  coinType: string,
): Promise<number> {
  const metadata = await client.getCoinMetadata({ coinType })
  if (!metadata) {
    throw new Error(`Coin type not found on-chain: ${coinType}`)
  }
  return metadata.decimals
}
