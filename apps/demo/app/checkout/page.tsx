'use client'

import { useState } from 'react'
import { WalletGuard } from '@/components/WalletGuard'
import { TxStatus } from '@/components/TxStatus'
import { CoinToggle } from '@/components/CoinToggle'
import { ProductCard } from '@/components/ProductCard'
import { DEMO_PRODUCTS, priceToAmount } from '@/lib/products'
import { usePaymentHook } from '@/lib/hooks'

export default function CheckoutPage() {
  const [selectedId, setSelectedId] = useState('pro')
  const [coin, setCoin] = useState('USDC')
  const { pay, status, error, result, reset } = usePaymentHook()

  const product = DEMO_PRODUCTS.find((p) => p.id === selectedId)!
  const amount = priceToAmount(product.priceUsd, coin)

  const handlePay = () => {
    pay({
      amount,
      coin,
      orderId: `demo_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    })
  }

  return (
    <div className="mx-auto max-w-2xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Checkout Demo
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-8">
        Choose a plan and pay
      </h1>

      {/* Product Selection */}
      <div className="grid gap-4 mb-8">
        {DEMO_PRODUCTS.map((p) => (
          <ProductCard
            key={p.id}
            product={p}
            selected={p.id === selectedId}
            onSelect={() => { setSelectedId(p.id); reset() }}
          />
        ))}
      </div>

      <WalletGuard>
        {/* Checkout Card */}
        <div className="rounded-2xl border border-ocean-foam/30 bg-white p-8 shadow-sm">
          <h2 className="text-xl font-semibold text-ocean-deep mb-6">Order Summary</h2>

          <div className="flex items-center justify-between mb-4">
            <span className="text-ocean-ink">{product.name}</span>
            <span className="text-lg font-bold text-ocean-deep">${product.priceUsd}</span>
          </div>

          <div className="flex items-center justify-between mb-6">
            <span className="text-sm text-ocean-ink">Pay with</span>
            <CoinToggle value={coin} onChange={(c) => { setCoin(c); reset() }} />
          </div>

          <div className="border-t border-ocean-foam/30 pt-4 mb-6">
            <div className="flex items-center justify-between">
              <span className="text-sm text-ocean-ink">Network</span>
              <span className="rounded-full bg-ocean-mist px-3 py-0.5 text-xs font-medium text-ocean-water">
                SUI Testnet
              </span>
            </div>
          </div>

          <button
            onClick={handlePay}
            disabled={status !== 'idle' && status !== 'error' && status !== 'rejected'}
            className="w-full rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal py-3.5 text-sm font-semibold text-white shadow-lg shadow-ocean-water/25 hover:shadow-ocean-water/40 transition-shadow disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Pay ${product.priceUsd} with {coin}
          </button>

          <TxStatus status={status} error={error} digest={result} onReset={reset} />
        </div>
      </WalletGuard>
    </div>
  )
}
