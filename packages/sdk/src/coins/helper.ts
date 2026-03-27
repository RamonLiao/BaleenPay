import { Transaction } from '@mysten/sui/transactions'
import type { SuiGrpcClient } from '@mysten/sui/grpc'

/**
 * Get coins of a specific type owned by `owner`, merge them if needed,
 * and split exact `amount`. Returns the split coin argument for PTB use.
 *
 * Handles:
 * - Single coin with exact amount → use directly
 * - Single coin with excess → split
 * - Multiple coins → merge then split
 * - SUI → use tx.gas as source (no getCoins needed)
 */
export async function prepareCoin(
  tx: Transaction,
  client: SuiGrpcClient,
  owner: string,
  coinType: string,
  amount: bigint,
): Promise<ReturnType<Transaction['splitCoins']>> {
  const isSUI = coinType === '0x2::sui::SUI'

  if (isSUI) {
    // For SUI, split from gas coin
    return tx.splitCoins(tx.gas, [amount])
  }

  // Fetch all coins of this type
  const { objects: coins } = await client.listCoins({
    owner,
    coinType,
  })

  if (!coins || coins.length === 0) {
    throw new Error(`No ${coinType} coins found for ${owner}`)
  }

  // Sort by balance descending — use largest coins first
  coins.sort((a, b) => Number(BigInt(b.balance) - BigInt(a.balance)))

  // Check total balance
  const totalBalance = coins.reduce((sum, c) => sum + BigInt(c.balance), 0n)
  if (totalBalance < amount) {
    throw new Error(
      `Insufficient ${coinType} balance: have ${totalBalance}, need ${amount}`
    )
  }

  if (coins.length === 1) {
    // Single coin — split from it
    const coinRef = tx.object(coins[0].objectId)
    return tx.splitCoins(coinRef, [amount])
  }

  // Multiple coins — merge into first, then split
  const primary = tx.object(coins[0].objectId)
  const rest = coins.slice(1).map(c => tx.object(c.objectId))
  tx.mergeCoins(primary, rest)
  return tx.splitCoins(primary, [amount])
}
