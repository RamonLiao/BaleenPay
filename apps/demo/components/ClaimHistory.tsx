'use client'

import type { ClaimEvent } from '@floatsync/react'
import { formatAmount, formatDate, truncateAddress } from '@/lib/format'

interface ClaimHistoryProps {
  claimEvents: ClaimEvent[]
  isLoading: boolean
}

export function ClaimHistory({ claimEvents, isLoading }: ClaimHistoryProps) {
  if (isLoading) {
    return (
      <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
        <p className="text-ocean-ink/60 animate-pulse text-sm">Loading claim history...</p>
      </div>
    )
  }

  if (claimEvents.length === 0) {
    return (
      <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6 flex items-center justify-center min-h-[200px]">
        <p className="text-ocean-ink/60 text-sm">No claims yet</p>
      </div>
    )
  }

  return (
    <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
      <h4 className="text-sm font-semibold text-ocean-deep mb-3">Claim History</h4>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-ocean-foam/30">
              <th className="text-left py-2 text-ocean-ink/60 font-medium">Date</th>
              <th className="text-right py-2 text-ocean-ink/60 font-medium">Amount</th>
              <th className="text-right py-2 text-ocean-ink/60 font-medium">TX</th>
            </tr>
          </thead>
          <tbody>
            {claimEvents.map((evt) => (
              <tr key={evt.txDigest} className="border-b border-ocean-foam/10 last:border-0">
                <td className="py-2 text-ocean-ink">{formatDate(evt.timestamp)}</td>
                <td className="py-2 text-right text-ocean-deep font-medium">
                  {formatAmount(evt.amount)} MIST
                </td>
                <td className="py-2 text-right">
                  <a
                    href={`https://testnet.suivision.xyz/txblock/${evt.txDigest}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-ocean-water hover:text-ocean-teal transition-colors"
                  >
                    {truncateAddress(evt.txDigest, 6)}
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
