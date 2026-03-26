import type { Plan } from '@/lib/products'

interface PlanCardProps {
  plan: Plan
  selected: boolean
  onSelect: () => void
}

export function PlanCard({ plan, selected, onSelect }: PlanCardProps) {
  return (
    <button
      onClick={onSelect}
      className={`relative w-full rounded-2xl border p-6 text-left transition-all ${
        selected
          ? 'border-ocean-water bg-ocean-mist shadow-md ring-2 ring-ocean-water/30'
          : 'border-ocean-foam/30 bg-white hover:border-ocean-foam hover:shadow-sm'
      }`}
    >
      {plan.badge && (
        <span className="absolute -top-3 right-4 rounded-full bg-ocean-sui px-3 py-0.5 text-xs font-semibold text-white">
          {plan.badge}
        </span>
      )}
      <h3 className="text-lg font-semibold text-ocean-deep">{plan.name}</h3>
      <p className="mt-2">
        <span className="text-2xl font-bold text-ocean-water">${plan.pricePerMonth}</span>
        <span className="text-sm text-ocean-ink">/month</span>
      </p>
      <p className="mt-1 text-sm text-ocean-ink">
        {plan.periods === 1 ? 'Billed monthly' : `${plan.periods} months prepaid — $${plan.pricePerMonth * plan.periods} total`}
      </p>
    </button>
  )
}
