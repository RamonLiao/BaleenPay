import type { Product } from '@/lib/products'

interface ProductCardProps {
  product: Product
  selected: boolean
  onSelect: () => void
}

export function ProductCard({ product, selected, onSelect }: ProductCardProps) {
  return (
    <button
      onClick={onSelect}
      className={`w-full rounded-2xl border p-6 text-left transition-all ${
        selected
          ? 'border-ocean-water bg-ocean-mist shadow-md ring-2 ring-ocean-water/30'
          : 'border-ocean-foam/30 bg-white hover:border-ocean-foam hover:shadow-sm'
      }`}
    >
      <h3 className="text-lg font-semibold text-ocean-deep">{product.name}</h3>
      <p className="mt-1 text-sm text-ocean-ink">{product.description}</p>
      <p className="mt-3 text-2xl font-bold text-ocean-water">${product.priceUsd}</p>
    </button>
  )
}
