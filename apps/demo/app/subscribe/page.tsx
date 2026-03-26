'use client'

import { useState } from 'react'
import { useSubscription } from '@floatsync/react'
import { WalletGuard } from '@/components/WalletGuard'
import { TxStatus } from '@/components/TxStatus'
import { CoinToggle } from '@/components/CoinToggle'
import { PlanCard } from '@/components/PlanCard'
import { DEMO_PLANS, priceToAmount } from '@/lib/products'

const PERIOD_MS = 30 * 24 * 60 * 60 * 1000 // 30 days

export default function SubscribePage() {
  const [selectedId, setSelectedId] = useState('monthly')
  const [coin, setCoin] = useState('USDC')
  const { subscribe, status, error, result, reset } = useSubscription()

  const plan = DEMO_PLANS.find((p) => p.id === selectedId)!
  const amountPerPeriod = priceToAmount(plan.pricePerMonth, coin)
  const total = plan.pricePerMonth * plan.periods

  const handleSubscribe = () => {
    subscribe({
      amountPerPeriod,
      periodMs: PERIOD_MS,
      prepaidPeriods: plan.periods,
      coin,
      orderId: `sub_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    })
  }

  return (
    <div className="mx-auto max-w-2xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Subscribe Demo
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-8">
        Choose a subscription plan
      </h1>

      {/* Plan Selection */}
      <div className="grid md:grid-cols-2 gap-4 mb-8">
        {DEMO_PLANS.map((p) => (
          <PlanCard
            key={p.id}
            plan={p}
            selected={p.id === selectedId}
            onSelect={() => { setSelectedId(p.id); reset() }}
          />
        ))}
      </div>

      <WalletGuard>
        {/* Subscription Card */}
        <div className="rounded-2xl border border-ocean-foam/30 bg-white p-8 shadow-sm">
          <h2 className="text-xl font-semibold text-ocean-deep mb-6">Subscription Summary</h2>

          <div className="space-y-3 mb-6">
            <div className="flex justify-between">
              <span className="text-ocean-ink">Plan</span>
              <span className="font-medium text-ocean-deep">{plan.name}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-ocean-ink">Per period</span>
              <span className="font-medium text-ocean-deep">${plan.pricePerMonth}/mo</span>
            </div>
            <div className="flex justify-between">
              <span className="text-ocean-ink">Prepaid periods</span>
              <span className="font-medium text-ocean-deep">{plan.periods} month{plan.periods > 1 ? 's' : ''}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-ocean-ink">Pay with</span>
              <CoinToggle value={coin} onChange={(c) => { setCoin(c); reset() }} />
            </div>
          </div>

          <div className="border-t border-ocean-foam/30 pt-4 mb-6">
            <div className="flex justify-between">
              <span className="font-semibold text-ocean-deep">Total upfront</span>
              <span className="text-xl font-bold text-ocean-water">${total}</span>
            </div>
          </div>

          <button
            onClick={handleSubscribe}
            disabled={status !== 'idle' && status !== 'error' && status !== 'rejected'}
            className="w-full rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal py-3.5 text-sm font-semibold text-white shadow-lg shadow-ocean-water/25 hover:shadow-ocean-water/40 transition-shadow disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Subscribe — ${total} with {coin}
          </button>

          <TxStatus status={status} error={error} digest={result} onReset={reset} />

          {status === 'success' && result && (
            <div className="mt-6 rounded-xl bg-emerald-50 border border-emerald-200 p-4">
              <p className="text-sm font-medium text-emerald-700 mb-2">Subscription Active</p>
              <p className="text-xs text-emerald-600">
                Your subscription is live on SUI testnet. In production, the merchant
                can process payments each period automatically.
              </p>
            </div>
          )}
        </div>
      </WalletGuard>
    </div>
  )
}
