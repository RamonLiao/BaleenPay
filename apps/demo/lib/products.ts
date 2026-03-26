export interface Product {
  id: string
  name: string
  description: string
  priceUsd: number
}

export const DEMO_PRODUCTS: Product[] = [
  { id: 'basic', name: 'Basic', description: 'Essential features for small projects', priceUsd: 19 },
  { id: 'pro', name: 'Pro', description: 'Advanced features for growing teams', priceUsd: 49 },
  { id: 'enterprise', name: 'Enterprise', description: 'Full platform access with priority support', priceUsd: 149 },
]

export interface Plan {
  id: string
  name: string
  pricePerMonth: number
  periods: number
  badge?: string
}

export const DEMO_PLANS: Plan[] = [
  { id: 'monthly', name: 'Monthly', pricePerMonth: 49, periods: 1 },
  { id: 'annual', name: 'Annual', pricePerMonth: 39, periods: 12, badge: 'Save 20%' },
]

/**
 * Convert USD price to coin amount in smallest unit.
 * For demo: 1 USD = 1_000_000 USDC (6 decimals), 1 USD = 1_000_000_000 SUI (9 decimals, assuming 1:1 for testnet).
 */
export function priceToAmount(priceUsd: number, coin: string): bigint {
  const decimals = coin === 'USDC' ? 6 : 9
  return BigInt(priceUsd) * 10n ** BigInt(decimals)
}
