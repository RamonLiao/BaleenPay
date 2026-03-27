import type { SuiGrpcClient } from '@mysten/sui/grpc'

/**
 * Validate that a coin type exists on-chain by checking CoinMetadata.
 * Returns decimals if found, throws if not.
 */
export async function validateCoinType(
  client: SuiGrpcClient,
  coinType: string,
): Promise<number> {
  const { coinMetadata: metadata } = await client.getCoinMetadata({ coinType })
  if (!metadata) {
    throw new Error(`Coin type not found on-chain: ${coinType}`)
  }
  return metadata.decimals
}
