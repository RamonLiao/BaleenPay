import type { ObjectId } from '../types.js'

export interface CoinConfig {
  type: string
  decimals: number
}

const TESTNET_COINS: Record<string, CoinConfig> = {
  USDC: {
    type: '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC',
    decimals: 6,
  },
  SUI: {
    type: '0x2::sui::SUI',
    decimals: 9,
  },
  USDB: {
    type: '0xe25a20601a1ecc2fa5ac9e5d37b52f9ce70a1ebe787856184ffb7dbe31dba4c1::stable_layer::Stablecoin',
    decimals: 6,
  },
}

const MAINNET_COINS: Record<string, CoinConfig> = {
  USDC: {
    type: '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC',
    decimals: 6,
  },
  SUI: {
    type: '0x2::sui::SUI',
    decimals: 9,
  },
}

const DEVNET_COINS: Record<string, CoinConfig> = {
  SUI: {
    type: '0x2::sui::SUI',
    decimals: 9,
  },
}

const COIN_MAPS: Record<string, Record<string, CoinConfig>> = {
  testnet: TESTNET_COINS,
  mainnet: MAINNET_COINS,
  devnet: DEVNET_COINS,
}

/**
 * Resolve a coin shorthand ('USDC', 'SUI') or full type string to a CoinConfig.
 * Full type strings (starting with '0x') are returned as-is with decimals = -1 (unknown).
 */
export function resolveCoin(network: string, coin: string): CoinConfig {
  // Full type string — pass through
  if (coin.startsWith('0x')) {
    return { type: coin, decimals: -1 }
  }

  const map = COIN_MAPS[network]
  if (!map) {
    throw new Error(`Unknown network: ${network}`)
  }

  const upper = coin.toUpperCase()
  const config = map[upper]
  if (!config) {
    throw new Error(
      `Unknown coin "${coin}" on ${network}. Available: ${Object.keys(map).join(', ')}`
    )
  }

  return config
}

/** Extract the type argument string from a full coin type for PTB usage */
export function coinTypeArg(coinType: string): string {
  return coinType
}
