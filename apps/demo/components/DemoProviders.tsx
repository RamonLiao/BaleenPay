'use client'

import { Nav } from '@/components/Nav'
import { Footer } from '@/components/Footer'

/**
 * Minimal providers for demo mode — no wallet, no chain, no QueryClient.
 * Pages use mock hooks from lib/hooks.ts which don't need any context.
 */
export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <>
      <DemoNav />
      <main className="pt-20 min-h-screen">
        {children}
      </main>
      <Footer />
    </>
  )
}

/** Simplified nav without ConnectButton (no wallet in demo mode) */
function DemoNav() {
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-white/95 backdrop-blur shadow-sm">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <a href="/" className="text-xl font-bold text-ocean-water">BaleenPay</a>
        <div className="flex items-center gap-6">
          {[
            { href: '/checkout', label: 'Checkout' },
            { href: '/subscribe', label: 'Subscribe' },
            { href: '/dashboard', label: 'Dashboard' },
            { href: '/developers', label: 'Developers' },
          ].map(({ href, label }) => (
            <a
              key={href}
              href={href}
              className="text-sm font-medium text-ocean-ink hover:text-ocean-water transition-colors"
            >
              {label}
            </a>
          ))}
          <span className="rounded-full bg-ocean-mist px-4 py-1.5 text-xs font-medium text-ocean-water">
            Demo Mode
          </span>
        </div>
      </div>
    </nav>
  )
}
