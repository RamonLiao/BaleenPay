/** Truncate a 0x... address to 0x1234...abcd */
export function truncateAddress(address: string, chars = 4): string {
  if (address.length <= chars * 2 + 2) return address
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`
}

/** Format MIST (u64) to human-readable SUI/USDC amount */
export function formatAmount(mist: bigint, decimals = 9): string {
  const divisor = 10n ** BigInt(decimals)
  const whole = mist / divisor
  const frac = mist % divisor
  if (frac === 0n) return whole.toString()
  const fracStr = frac.toString().padStart(decimals, '0').replace(/0+$/, '')
  return `${whole}.${fracStr}`
}

/** Format epoch ms to locale date string */
export function formatDate(epochMs: number): string {
  return new Date(epochMs).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}
