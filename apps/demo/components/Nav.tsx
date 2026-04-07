'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { ConnectButton } from '@mysten/dapp-kit-react/ui'

const NAV_GROUPS = [
  {
    role: 'Pay',
    links: [
      { href: '/checkout', label: 'Checkout' },
      { href: '/subscribe', label: 'Subscribe' },
    ],
  },
  {
    role: 'Merchant',
    links: [{ href: '/dashboard', label: 'Dashboard' }],
  },
  {
    role: 'Build',
    links: [{ href: '/developers', label: 'Developers' }],
  },
]

export function Nav() {
  const [scrolled, setScrolled] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled || mobileOpen
          ? 'bg-white/95 backdrop-blur shadow-sm'
          : 'bg-transparent'
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <Link href="/" className="text-xl font-bold text-ocean-water">
          BaleenPay
        </Link>

        {/* Desktop nav */}
        <div className="hidden md:flex items-center gap-1">
          {NAV_GROUPS.map((group, i) => (
            <div key={group.role} className="flex items-center">
              {i > 0 && (
                <span className="mx-2 h-4 w-px bg-ocean-foam/60" />
              )}
              <span className="mr-1.5 text-[10px] font-semibold uppercase tracking-wider text-ocean-sky/70">
                {group.role}
              </span>
              {group.links.map(({ href, label }) => (
                <Link
                  key={href}
                  href={href}
                  className="rounded-md px-2.5 py-1 text-sm font-medium text-ocean-ink hover:bg-ocean-mist hover:text-ocean-water transition-colors"
                >
                  {label}
                </Link>
              ))}
            </div>
          ))}
          <span className="mx-2 h-4 w-px bg-ocean-foam/60" />
          <ConnectButton />
        </div>

        {/* Mobile hamburger */}
        <button
          className="md:hidden p-2 text-ocean-ink"
          onClick={() => setMobileOpen((v) => !v)}
          aria-label="Toggle menu"
        >
          <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            {mobileOpen ? (
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            ) : (
              <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h16M4 18h16" />
            )}
          </svg>
        </button>
      </div>

      {/* Mobile menu */}
      {mobileOpen && (
        <div className="md:hidden border-t border-ocean-foam/30 bg-white/95 backdrop-blur px-6 pb-4">
          {NAV_GROUPS.map((group) => (
            <div key={group.role} className="py-2">
              <span className="text-[10px] font-semibold uppercase tracking-wider text-ocean-sky/70">
                {group.role}
              </span>
              <div className="mt-1 flex flex-col gap-1">
                {group.links.map(({ href, label }) => (
                  <Link
                    key={href}
                    href={href}
                    onClick={() => setMobileOpen(false)}
                    className="rounded-md px-3 py-2 text-sm font-medium text-ocean-ink hover:bg-ocean-mist hover:text-ocean-water transition-colors"
                  >
                    {label}
                  </Link>
                ))}
              </div>
            </div>
          ))}
          <div className="pt-2 border-t border-ocean-foam/30">
            <ConnectButton />
          </div>
        </div>
      )}
    </nav>
  )
}
