'use client'

import { useMerchant, usePaymentHistory } from '@floatsync/react'
import { useDAppKit, useCurrentAccount } from '@mysten/dapp-kit-react'
import { buildClaimYield, buildSelfPause, buildSelfUnpause } from '@floatsync/sdk'
import { useState } from 'react'
import { WalletGuard } from '@/components/WalletGuard'
import { TxStatus } from '@/components/TxStatus'
import { StatCard } from '@/components/StatCard'
import { PaymentTable } from '@/components/PaymentTable'
import { DEMO_CONFIG, MERCHANT_CAP_ID } from '@/lib/config'
import { formatAmount } from '@/lib/format'
import type { MutationStatus } from '@floatsync/react'

export default function DashboardPage() {
  const account = useCurrentAccount()
  const dAppKit = useDAppKit()
  const { merchant, isLoading: merchantLoading, refetch: refetchMerchant } = useMerchant()
  const { events, isLoading: historyLoading, hasNextPage, fetchNextPage } = usePaymentHistory()

  // Admin action state
  const [actionStatus, setActionStatus] = useState<MutationStatus>('idle')
  const [actionError, setActionError] = useState<Error | null>(null)
  const [actionDigest, setActionDigest] = useState<string | null>(null)

  const resetAction = () => {
    setActionStatus('idle')
    setActionError(null)
    setActionDigest(null)
  }

  const executeAdminTx = async (buildFn: () => import('@mysten/sui/transactions').Transaction) => {
    try {
      resetAction()
      setActionStatus('signing')
      const tx = buildFn()
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      // NOTE: v2 dapp-kit returns flat result with .digest — v1 pattern (FailedTransaction/Transaction) kept for now
      if (result.FailedTransaction) {
        throw new Error(result.FailedTransaction.status.error?.message ?? 'Transaction failed')
      }
      setActionDigest(result.Transaction.digest)
      setActionStatus('success')
      refetchMerchant()
    } catch (err) {
      const e = err instanceof Error ? err : new Error(String(err))
      setActionError(e)
      setActionStatus(e.message.toLowerCase().includes('reject') ? 'rejected' : 'error')
    }
  }

  return (
    <div className="mx-auto max-w-5xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Merchant Dashboard
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-8">
        Dashboard
      </h1>

      <WalletGuard>
        {merchantLoading ? (
          <p className="text-ocean-ink">Loading merchant data...</p>
        ) : !merchant ? (
          <div className="rounded-2xl border border-ocean-foam/30 bg-white p-12 text-center">
            <p className="text-ocean-ink">No merchant account found</p>
            <p className="text-sm text-ocean-ink/60 mt-1">
              The connected wallet does not own a MerchantCap for this demo merchant.
            </p>
          </div>
        ) : (
          <>
            {/* Merchant Header */}
            <div className="flex items-center gap-3 mb-8">
              <h2 className="text-xl font-semibold text-ocean-deep">{merchant.brandName}</h2>
              {merchant.paused && (
                <span className="rounded-full bg-amber-100 px-3 py-0.5 text-xs font-semibold text-amber-700">
                  Paused
                </span>
              )}
            </div>

            {/* Stats Grid */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
              <StatCard
                label="Total Received"
                value={formatAmount(merchant.totalReceived)}
                sub="MIST"
              />
              <StatCard
                label="Idle Principal"
                value={formatAmount(merchant.idlePrincipal)}
                sub="In escrow"
              />
              <StatCard
                label="Accrued Yield"
                value={formatAmount(merchant.accruedYield)}
                sub="Claimable"
              />
              <StatCard
                label="Active Subscriptions"
                value={String(merchant.activeSubscriptions)}
              />
            </div>

            {/* Admin Actions */}
            <div className="grid md:grid-cols-2 gap-4 mb-8">
              {/* Yield Card */}
              <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
                <h3 className="text-lg font-semibold text-ocean-deep mb-2">Claim Yield</h3>
                <p className="text-sm text-ocean-ink mb-4">
                  Accrued: {formatAmount(merchant.accruedYield)} MIST
                </p>
                <button
                  onClick={() => executeAdminTx(() => buildClaimYield(DEMO_CONFIG, MERCHANT_CAP_ID))}
                  disabled={merchant.accruedYield === 0n || (actionStatus !== 'idle' && actionStatus !== 'error' && actionStatus !== 'rejected')}
                  className="rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal px-6 py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Claim Yield
                </button>
              </div>

              {/* Pause Toggle */}
              <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
                <h3 className="text-lg font-semibold text-ocean-deep mb-2">Merchant Status</h3>
                <p className="text-sm text-ocean-ink mb-4">
                  {merchant.paused ? 'Merchant is paused — no payments accepted' : 'Merchant is active'}
                </p>
                <button
                  onClick={() =>
                    executeAdminTx(() =>
                      merchant.paused
                        ? buildSelfUnpause(DEMO_CONFIG, MERCHANT_CAP_ID)
                        : buildSelfPause(DEMO_CONFIG, MERCHANT_CAP_ID)
                    )
                  }
                  disabled={actionStatus !== 'idle' && actionStatus !== 'error' && actionStatus !== 'rejected'}
                  className={`rounded-xl px-6 py-2.5 text-sm font-semibold shadow-md disabled:opacity-50 disabled:cursor-not-allowed ${
                    merchant.paused
                      ? 'bg-emerald-500 text-white'
                      : 'bg-amber-500 text-white'
                  }`}
                >
                  {merchant.paused ? 'Unpause' : 'Pause'}
                </button>
              </div>
            </div>

            <TxStatus status={actionStatus} error={actionError} digest={actionDigest} onReset={resetAction} />

            {/* Payment History */}
            <div className="mt-8">
              <h3 className="text-lg font-semibold text-ocean-deep mb-4">Payment History</h3>
              <PaymentTable
                events={events}
                isLoading={historyLoading}
                hasNextPage={hasNextPage}
                onLoadMore={fetchNextPage}
              />
            </div>
          </>
        )}
      </WalletGuard>
    </div>
  )
}
