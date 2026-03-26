'use client'

const COINS = [
  { id: 'SUI', label: 'SUI', decimals: 9 },
  { id: 'USDC', label: 'USDC', decimals: 6 },
] as const

interface CoinToggleProps {
  value: string
  onChange: (coin: string) => void
}

export function CoinToggle({ value, onChange }: CoinToggleProps) {
  return (
    <div className="flex gap-2">
      {COINS.map((coin) => (
        <button
          key={coin.id}
          onClick={() => onChange(coin.id)}
          className={`rounded-full px-4 py-1.5 text-sm font-medium transition-all ${
            value === coin.id
              ? 'bg-ocean-water text-white shadow-md'
              : 'bg-ocean-mist text-ocean-ink hover:bg-ocean-foam'
          }`}
        >
          {coin.label}
        </button>
      ))}
    </div>
  )
}

/** Get decimal places for a coin shorthand */
export function coinDecimals(coin: string): number {
  return COINS.find((c) => c.id === coin)?.decimals ?? 9
}
