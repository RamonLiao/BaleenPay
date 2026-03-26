'use client'

import { createDAppKit } from '@mysten/dapp-kit-core'
import { DAppKitProvider } from '@mysten/dapp-kit-react'
import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { FloatSyncProvider } from '@floatsync/react'
import { Nav } from '@/components/Nav'
import { Footer } from '@/components/Footer'
import { DEMO_CONFIG } from '@/lib/config'

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

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <DAppKitProvider dAppKit={dAppKit}>
        <FloatSyncProvider config={DEMO_CONFIG}>
          <Nav />
          <main className="pt-20 min-h-screen">
            {children}
          </main>
          <Footer />
        </FloatSyncProvider>
      </DAppKitProvider>
    </QueryClientProvider>
  )
}
