'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { ConnectButton } from '@mysten/dapp-kit-react/ui'

const NAV_LINKS = [
  { href: '/checkout', label: 'Checkout' },
  { href: '/subscribe', label: 'Subscribe' },
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/developers', label: 'Developers' },
]

export function Nav() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled
          ? 'bg-white/95 backdrop-blur shadow-sm'
          : 'bg-transparent'
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <Link href="/" className="text-xl font-bold text-ocean-water">
          FloatSync
        </Link>
        <div className="flex items-center gap-6">
          {NAV_LINKS.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className="text-sm font-medium text-ocean-ink hover:text-ocean-water transition-colors"
            >
              {label}
            </Link>
          ))}
          <ConnectButton />
        </div>
      </div>
    </nav>
  )
}
