import type { MutationStatus } from '@floatsync/react'
import { SUISCAN_URL } from '@/lib/config'

interface TxStatusProps {
  status: MutationStatus
  error: Error | null
  digest: string | null
  onReset?: () => void
}

const STATUS_CONFIG: Record<string, { label: string; color: string }> = {
  building: { label: 'Preparing transaction...', color: 'text-ocean-water' },
  signing: { label: 'Confirm in your wallet...', color: 'text-ocean-sui' },
  confirming: { label: 'Confirming on SUI...', color: 'text-ocean-teal' },
  success: { label: 'Payment successful!', color: 'text-emerald-600' },
  error: { label: 'Transaction failed', color: 'text-red-500' },
  rejected: { label: 'Transaction cancelled', color: 'text-amber-500' },
}

export function TxStatus({ status, error, digest, onReset }: TxStatusProps) {
  if (status === 'idle') return null

  const config = STATUS_CONFIG[status]
  if (!config) return null

  return (
    <div className="mt-4 rounded-xl border border-ocean-foam/30 bg-ocean-mist/50 p-4">
      <p className={`text-sm font-medium ${config.color}`}>
        {(status === 'building' || status === 'signing' || status === 'confirming') && (
          <span className="inline-block animate-spin mr-2">&#9696;</span>
        )}
        {config.label}
      </p>

      {status === 'success' && digest && (
        <a
          href={`${SUISCAN_URL}/${digest}`}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-2 inline-block text-sm text-ocean-water underline"
        >
          View on SuiScan &rarr;
        </a>
      )}

      {(status === 'error' || status === 'rejected') && (
        <div className="mt-2">
          {error && <p className="text-sm text-red-400">{error.message}</p>}
          {onReset && (
            <button
              onClick={onReset}
              className="mt-2 text-sm text-ocean-water underline"
            >
              Try again
            </button>
          )}
        </div>
      )}
    </div>
  )
}
