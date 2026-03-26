'use client'

import { createDAppKit } from '@mysten/dapp-kit-core'
import { DAppKitProvider } from '@mysten/dapp-kit-react'
import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { FloatSyncProvider } from '@floatsync/react'
import { DEMO_CONFIG } from '@/lib/config'
import './globals.css'

const dAppKit = createDAppKit({
  networks: ['testnet'],
  createClient: () =>
    new SuiJsonRpcClient({
      url: getJsonRpcFullnodeUrl('testnet'),
      network: 'testnet',
    }),
  defaultNetwork: 'testnet',
})

const queryClient = new QueryClient()

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-ocean-surface text-ocean-deep font-sans antialiased">
        <QueryClientProvider client={queryClient}>
          <DAppKitProvider dAppKit={dAppKit}>
            <FloatSyncProvider config={DEMO_CONFIG}>
              {children}
            </FloatSyncProvider>
          </DAppKitProvider>
        </QueryClientProvider>
      </body>
    </html>
  )
}
