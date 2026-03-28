'use client'

import dynamic from 'next/dynamic'

const DEMO_MODE = process.env.NEXT_PUBLIC_DEMO_MODE === 'true'

const RealProviders = dynamic(
  () => import('@/components/Providers').then((m) => m.Providers),
  { ssr: false },
)

const DemoProviders = dynamic(
  () => import('@/components/DemoProviders').then((m) => m.Providers),
  { ssr: false },
)

export function ClientShell({ children }: { children: React.ReactNode }) {
  const Shell = DEMO_MODE ? DemoProviders : RealProviders
  return <Shell>{children}</Shell>
}
