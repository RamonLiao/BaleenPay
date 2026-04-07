'use client'

import { useCurrentAccount } from '@mysten/dapp-kit-react'
import { ConnectButton } from '@mysten/dapp-kit-react/ui'

export function WalletGuard({ children }: { children: React.ReactNode }) {
  const account = useCurrentAccount()

  if (!account) {
    return (
      <div className="flex flex-col items-center justify-center gap-6 py-24">
        <div className="rounded-2xl border border-ocean-foam/30 bg-white p-12 text-center shadow-sm">
          <h2 className="text-2xl font-bold text-ocean-deep mb-2">Connect Your Wallet</h2>
          <p className="text-ocean-ink mb-6">Connect a SUI wallet to continue</p>
          <ConnectButton />
        </div>
      </div>
    )
  }

  return <>{children}</>
}
