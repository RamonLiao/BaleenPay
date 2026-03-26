import type { FloatSyncEventData } from '@floatsync/sdk'
import { truncateAddress, formatAmount, formatDate } from '@/lib/format'
import { SUISCAN_URL } from '@/lib/config'

interface PaymentTableProps {
  events: FloatSyncEventData[]
  isLoading: boolean
  hasNextPage: boolean
  onLoadMore: () => void
}

export function PaymentTable({ events, isLoading, hasNextPage, onLoadMore }: PaymentTableProps) {
  if (isLoading && events.length === 0) {
    return <p className="text-sm text-ocean-ink py-8 text-center">Loading payment history...</p>
  }

  if (events.length === 0) {
    return (
      <div className="rounded-2xl border border-ocean-foam/30 bg-white p-12 text-center">
        <p className="text-ocean-ink">No payments yet</p>
        <p className="text-sm text-ocean-ink/60 mt-1">Payments will appear here after the first transaction</p>
      </div>
    )
  }

  return (
    <div className="rounded-2xl border border-ocean-foam/30 bg-white overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-ocean-foam/30 bg-ocean-mist/50">
            <th className="px-4 py-3 text-left font-medium text-ocean-ink">Time</th>
            <th className="px-4 py-3 text-left font-medium text-ocean-ink">Payer</th>
            <th className="px-4 py-3 text-right font-medium text-ocean-ink">Amount</th>
            <th className="px-4 py-3 text-left font-medium text-ocean-ink">Order ID</th>
          </tr>
        </thead>
        <tbody>
          {events.map((e, i) => (
            <tr key={`${e.orderId}-${i}`} className="border-b border-ocean-foam/10 hover:bg-ocean-mist/30">
              <td className="px-4 py-3 text-ocean-ink">
                {e.timestamp ? formatDate(e.timestamp) : '—'}
              </td>
              <td className="px-4 py-3 font-mono text-xs text-ocean-ink">
                {e.payer ? truncateAddress(e.payer) : '—'}
              </td>
              <td className="px-4 py-3 text-right font-medium text-ocean-deep">
                {e.amount != null ? formatAmount(e.amount) : '—'}
              </td>
              <td className="px-4 py-3 font-mono text-xs text-ocean-ink">
                {e.orderId ?? '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {hasNextPage && (
        <div className="p-4 text-center border-t border-ocean-foam/10">
          <button
            onClick={onLoadMore}
            className="text-sm text-ocean-water hover:text-ocean-sui transition-colors"
          >
            Load more
          </button>
        </div>
      )}
    </div>
  )
}
