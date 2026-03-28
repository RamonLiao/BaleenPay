# BaleenPay Demo App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 5-page Next.js demo app (Landing, Checkout, Subscribe, Dashboard, Developers) that showcases BaleenPay payment infrastructure on SUI testnet with real wallet transactions.

**Architecture:** Next.js 15 App Router with Tailwind 4, consuming `@baleenpay/sdk` and `@baleenpay/react` workspace packages. Provider stack: WalletProvider → QueryClientProvider → BaleenPayProvider. All pages are client-rendered (wallet interactions require browser). Ocean-themed visual design (Stripe layout × SUI palette).

**Tech Stack:** Next.js 15, React 19, Tailwind CSS 4, @baleenpay/sdk (workspace), @baleenpay/react (workspace), @mysten/dapp-kit-react ^2.0.0, @mysten/sui ^2.8.0, @tanstack/react-query ^5

**Spec:** `docs/superpowers/specs/2026-03-26-baleenpay-demo-app-design.md`

**Testnet Config (from `move/baleenpay/deployed.testnet.json`):**
- packageId: `0xe0eb53cce531ab129e499b06ed1a858bb64da08e6c53c18ab4c85ef01306b32a`
- merchantId: `0x4db0ff62d5402f3970028995312a4fd0c243cef9ce6d1e4ace77667155c17c24`
- registryId: `0x2b0584da2655e87873a72977a36741d64e59d68e550016ebb38be5fe243a321f`
- routerConfigId: `0x0bae66f0910b0d22b30d6be5bc2c3f0272ef9c917b34b041608c0fbd31264e8e`
- MerchantCap: `0x93e30ffb648ddbee6a93518f82eb332a39c1b3457dc7c02544fb105e02d520e2`

---

## File Structure

```
apps/demo/
├── app/
│   ├── layout.tsx              # Root layout: Providers + Nav + Footer
│   ├── page.tsx                # Landing page
│   ├── checkout/page.tsx       # One-time payment flow
│   ├── subscribe/page.tsx      # Subscription flow
│   ├── dashboard/page.tsx      # Merchant dashboard
│   └── developers/page.tsx     # Code snippet showcase
├── components/
│   ├── Nav.tsx                 # Sticky nav with transparent→white scroll
│   ├── Footer.tsx              # Deep ocean footer
│   ├── WalletGuard.tsx         # Connect prompt if no wallet
│   ├── TxStatus.tsx            # Transaction state indicator (shared)
│   ├── CoinToggle.tsx          # SUI/USDC toggle (shared)
│   ├── ProductCard.tsx         # Selectable product card (checkout)
│   ├── PlanCard.tsx            # Subscription plan card (subscribe)
│   ├── StatCard.tsx            # Stats metric card (dashboard)
│   ├── PaymentTable.tsx        # Payment history table (dashboard)
│   └── CodeSnippet.tsx         # Syntax-highlighted code block (developers)
├── lib/
│   ├── config.ts               # Testnet config constants
│   ├── products.ts             # Demo product/plan definitions
│   ├── snippets.ts             # Code snippet strings
│   └── format.ts               # Shared formatting helpers (address, amount, date)
├── tailwind.config.ts
├── next.config.ts
├── tsconfig.json
└── package.json
```

**Design rationale:** Flat component structure (no nested directories) — the demo has ~10 components, nested folders add navigation cost without benefit. `lib/` holds static data and pure helpers. Each page is self-contained with its components imported directly.

---

## Task 1: Project Scaffold + Providers

**Files:**
- Create: `apps/demo/package.json`
- Create: `apps/demo/next.config.ts`
- Create: `apps/demo/tsconfig.json`
- Create: `apps/demo/tailwind.config.ts`
- Create: `apps/demo/app/layout.tsx`
- Create: `apps/demo/lib/config.ts`
- Create: `apps/demo/app/page.tsx` (placeholder)

### Steps

- [ ] **Step 1: Create `apps/demo/package.json`**

```json
{
  "name": "@baleenpay/demo",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "next dev --port 3100",
    "build": "next build",
    "start": "next start",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@baleenpay/sdk": "workspace:*",
    "@baleenpay/react": "workspace:*",
    "@mysten/dapp-kit-react": "^2.0.0",
    "@mysten/sui": "^2.8.0",
    "@tanstack/react-query": "^5.60.0",
    "next": "^15.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/postcss": "^4.0.0",
    "typescript": "^5.7.0"
  }
}
```

- [ ] **Step 2: Create `apps/demo/next.config.ts`**

```ts
import type { NextConfig } from 'next'

const config: NextConfig = {
  transpilePackages: ['@baleenpay/sdk', '@baleenpay/react'],
}

export default config
```

- [ ] **Step 3: Create `apps/demo/tsconfig.json`**

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "ES2022"],
    "jsx": "preserve",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "noEmit": true,
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": {
      "@/*": ["./*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 4: Create `apps/demo/tailwind.config.ts`**

Tailwind 4 uses CSS-first config, but we define the ocean palette as a JS config for the `theme` extension.

```ts
import type { Config } from 'tailwindcss'

export default {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ocean: {
          deep: '#0B1426',
          midnight: '#0D2137',
          ink: '#1A3A5C',
          water: '#2389E8',
          sui: '#4DA2FF',
          teal: '#0EA5E9',
          sky: '#6FBCFF',
          foam: '#B8DEFF',
          mist: '#E8F4FF',
          surface: '#F7FBFF',
        },
      },
      fontFamily: {
        sans: ['Inter', '-apple-system', 'system-ui', 'sans-serif'],
        mono: ['SF Mono', 'Fira Code', 'monospace'],
      },
    },
  },
  plugins: [],
} satisfies Config
```

- [ ] **Step 5: Create `apps/demo/app/globals.css`**

```css
@import 'tailwindcss';
@config '../tailwind.config.ts';
```

- [ ] **Step 6: Create `apps/demo/lib/config.ts`**

```ts
import type { BaleenPayConfig } from '@baleenpay/sdk'

export const DEMO_CONFIG: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0xe0eb53cce531ab129e499b06ed1a858bb64da08e6c53c18ab4c85ef01306b32a',
  merchantId: '0x4db0ff62d5402f3970028995312a4fd0c243cef9ce6d1e4ace77667155c17c24',
  registryId: '0x2b0584da2655e87873a72977a36741d64e59d68e550016ebb38be5fe243a321f',
  routerConfigId: '0x0bae66f0910b0d22b30d6be5bc2c3f0272ef9c917b34b041608c0fbd31264e8e',
}

/** MerchantCap object ID — needed for dashboard admin actions */
export const MERCHANT_CAP_ID = '0x93e30ffb648ddbee6a93518f82eb332a39c1b3457dc7c02544fb105e02d520e2'

/** SuiScan URL for tx digest links */
export const SUISCAN_URL = 'https://suiscan.xyz/testnet/tx'
```

- [ ] **Step 7: Create `apps/demo/app/layout.tsx`**

```tsx
'use client'

import { createNetworkConfig, SuiClientProvider, WalletProvider } from '@mysten/dapp-kit-react'
import { getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BaleenPayProvider } from '@baleenpay/react'
import { DEMO_CONFIG } from '@/lib/config'
import './globals.css'

const { networkConfig } = createNetworkConfig({
  testnet: { url: getJsonRpcFullnodeUrl('testnet') },
})

const queryClient = new QueryClient()

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-ocean-surface text-ocean-deep font-sans antialiased">
        <QueryClientProvider client={queryClient}>
          <SuiClientProvider networks={networkConfig} defaultNetwork="testnet">
            <WalletProvider autoConnect>
              <BaleenPayProvider config={DEMO_CONFIG}>
                {children}
              </BaleenPayProvider>
            </WalletProvider>
          </SuiClientProvider>
        </QueryClientProvider>
      </body>
    </html>
  )
}
```

**Note:** `@mysten/dapp-kit-react` v2 uses `createNetworkConfig` + `SuiClientProvider` + `WalletProvider` as its provider stack. The `BaleenPayProvider` wraps inside so it can access the SUI client context.

- [ ] **Step 8: Create placeholder `apps/demo/app/page.tsx`**

```tsx
export default function LandingPage() {
  return (
    <main className="flex min-h-screen items-center justify-center">
      <h1 className="text-4xl font-bold text-ocean-water">BaleenPay Demo</h1>
    </main>
  )
}
```

- [ ] **Step 9: Install dependencies and verify build**

```bash
cd /Users/ramonliao/Documents/Code/Project/Web3/BlockchainDev/SUI/Projects/BaleenPay
pnpm install
pnpm --filter @baleenpay/sdk build
pnpm --filter @baleenpay/react build
pnpm --filter @baleenpay/demo typecheck
```

Expected: All pass. If dapp-kit-react import types mismatch, check `@mysten/dapp-kit-react` v2 exports — `createNetworkConfig`, `SuiClientProvider`, `WalletProvider`, `ConnectButton`, `useCurrentAccount`, `useDAppKit` should all be available.

- [ ] **Step 10: Verify dev server starts**

```bash
pnpm --filter @baleenpay/demo dev
```

Expected: Next.js dev server on http://localhost:3100, renders "BaleenPay Demo" text.

- [ ] **Step 11: Commit**

```bash
git add apps/demo/
git commit -m "feat(demo): scaffold Next.js 15 app with provider stack + testnet config"
```

---

## Task 2: Shared Layout Components (Nav + Footer) + Format Helpers

**Files:**
- Create: `apps/demo/components/Nav.tsx`
- Create: `apps/demo/components/Footer.tsx`
- Create: `apps/demo/lib/format.ts`
- Modify: `apps/demo/app/layout.tsx` (add Nav + Footer)

### Steps

- [ ] **Step 1: Create `apps/demo/lib/format.ts`**

```ts
/** Truncate a 0x... address to 0x1234...abcd */
export function truncateAddress(address: string, chars = 4): string {
  if (address.length <= chars * 2 + 2) return address
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`
}

/** Format MIST (u64) to human-readable SUI/USDC amount */
export function formatAmount(mist: bigint, decimals = 9): string {
  const divisor = 10n ** BigInt(decimals)
  const whole = mist / divisor
  const frac = mist % divisor
  if (frac === 0n) return whole.toString()
  const fracStr = frac.toString().padStart(decimals, '0').replace(/0+$/, '')
  return `${whole}.${fracStr}`
}

/** Format epoch ms to locale date string */
export function formatDate(epochMs: number): string {
  return new Date(epochMs).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}
```

- [ ] **Step 2: Create `apps/demo/components/Nav.tsx`**

```tsx
'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { ConnectButton } from '@mysten/dapp-kit-react'

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
          BaleenPay
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
```

- [ ] **Step 3: Create `apps/demo/components/Footer.tsx`**

```tsx
export function Footer() {
  return (
    <footer className="bg-ocean-deep text-ocean-foam/60 py-12">
      <div className="mx-auto max-w-6xl px-6 flex items-center justify-between">
        <p className="text-sm">BaleenPay — Payments infrastructure for the onchain economy</p>
        <p className="text-sm">Built on SUI &middot; Testnet Demo</p>
      </div>
    </footer>
  )
}
```

- [ ] **Step 4: Add Nav + Footer to layout**

In `apps/demo/app/layout.tsx`, import and render Nav + Footer around `{children}`:

```tsx
// Add imports at top:
import { Nav } from '@/components/Nav'
import { Footer } from '@/components/Footer'

// In the body, wrap children:
<Nav />
<main className="pt-20 min-h-screen">
  {children}
</main>
<Footer />
```

The `pt-20` compensates for the fixed nav height.

- [ ] **Step 5: Verify typecheck + dev server**

```bash
pnpm --filter @baleenpay/demo typecheck
```

Expected: PASS. Check dev server shows nav + footer.

- [ ] **Step 6: Commit**

```bash
git add apps/demo/components/Nav.tsx apps/demo/components/Footer.tsx apps/demo/lib/format.ts apps/demo/app/layout.tsx
git commit -m "feat(demo): Nav + Footer + format helpers"
```

---

## Task 3: Shared Components (WalletGuard, TxStatus, CoinToggle)

**Files:**
- Create: `apps/demo/components/WalletGuard.tsx`
- Create: `apps/demo/components/TxStatus.tsx`
- Create: `apps/demo/components/CoinToggle.tsx`

### Steps

- [ ] **Step 1: Create `apps/demo/components/WalletGuard.tsx`**

Shows connect prompt when wallet is not connected. Wraps page content.

```tsx
'use client'

import { useCurrentAccount } from '@mysten/dapp-kit-react'
import { ConnectButton } from '@mysten/dapp-kit-react'

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
```

- [ ] **Step 2: Create `apps/demo/components/TxStatus.tsx`**

Renders transaction state transitions (building → signing → confirming → success/error).

```tsx
import type { MutationStatus } from '@baleenpay/react'
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
```

- [ ] **Step 3: Create `apps/demo/components/CoinToggle.tsx`**

SUI / USDC toggle badges.

```tsx
'use client'

const COINS = [
  { id: 'SUI', label: 'SUI', decimals: 9 },
  { id: 'USDC', label: 'USDC', decimals: 6 },
] as const

interface CoinToggleProps {
  value: string
  onChange: (coin: string) => void
}

export function CoinToggle({ value, onChange }: CoinToggleProps) {
  return (
    <div className="flex gap-2">
      {COINS.map((coin) => (
        <button
          key={coin.id}
          onClick={() => onChange(coin.id)}
          className={`rounded-full px-4 py-1.5 text-sm font-medium transition-all ${
            value === coin.id
              ? 'bg-ocean-water text-white shadow-md'
              : 'bg-ocean-mist text-ocean-ink hover:bg-ocean-foam'
          }`}
        >
          {coin.label}
        </button>
      ))}
    </div>
  )
}

/** Get decimal places for a coin shorthand */
export function coinDecimals(coin: string): number {
  return COINS.find((c) => c.id === coin)?.decimals ?? 9
}
```

- [ ] **Step 4: Typecheck**

```bash
pnpm --filter @baleenpay/demo typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/demo/components/WalletGuard.tsx apps/demo/components/TxStatus.tsx apps/demo/components/CoinToggle.tsx
git commit -m "feat(demo): shared components — WalletGuard, TxStatus, CoinToggle"
```

---

## Task 4: Landing Page

**Files:**
- Create: `apps/demo/lib/snippets.ts` (partial — code preview snippet only)
- Modify: `apps/demo/app/page.tsx`

### Steps

- [ ] **Step 1: Create `apps/demo/lib/snippets.ts`** (start with hero code preview)

```ts
export const HERO_CODE_SNIPPET = `import { BaleenPay } from '@baleenpay/sdk'

const fs = new BaleenPay({
  network: 'testnet',
  packageId: '0xe0eb...306b32a',
  merchantId: '0x4db0...c17c24',
})

// Accept a payment — 4 lines
const { tx } = await fs.pay({
  amount: 49_000_000n,
  coin: 'USDC',
  orderId: 'order_001',
}, senderAddress)`
```

- [ ] **Step 2: Build the Landing page**

Replace `apps/demo/app/page.tsx` with the full landing page:

```tsx
import Link from 'next/link'

const FEATURES = [
  { title: 'One-Time Payments', desc: 'Accept crypto payments with order ID deduplication and instant settlement.' },
  { title: 'Subscriptions', desc: 'Recurring payments with prepaid periods, auto-processing, and cancellation.' },
  { title: 'Yield Generation', desc: 'Idle merchant funds earn yield automatically via DeFi routing.' },
  { title: 'Admin Controls', desc: 'Self-pause, admin freeze, and dual-pause model for regulatory compliance.' },
  { title: 'Instant Settlement', desc: 'Sub-second finality on SUI. No 2-day bank settlement wait.' },
  { title: 'Developer SDK', desc: 'TypeScript SDK + React hooks. Stripe-like DX for Web3 payments.' },
]

const STATS = [
  { value: '<1s', label: 'Settlement Time' },
  { value: '$0.001', label: 'Transaction Cost' },
  { value: 'Multi-Coin', label: 'SUI, USDC & More' },
  { value: 'On-Chain', label: 'Full Transparency' },
]

export default function LandingPage() {
  return (
    <>
      {/* Hero */}
      <section className="relative overflow-hidden bg-gradient-to-br from-ocean-deep via-ocean-midnight to-ocean-deep py-32">
        <div className="absolute top-0 right-0 w-[600px] h-[600px] rounded-full bg-ocean-water/5 blur-3xl" />
        <div className="relative mx-auto max-w-6xl px-6 text-center">
          <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-4">
            Payments Infrastructure
          </p>
          <h1 className="text-5xl md:text-6xl font-bold text-white tracking-tight leading-tight">
            Payments infrastructure for<br />the onchain economy
          </h1>
          <p className="mt-6 text-lg text-ocean-foam/70 max-w-2xl mx-auto">
            Accept payments, manage subscriptions, and earn yield — all on SUI.
            Stripe-level DX meets Web3 transparency.
          </p>
          <div className="mt-10 flex items-center justify-center gap-4">
            <Link
              href="/checkout"
              className="rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal px-8 py-3 text-sm font-semibold text-white shadow-lg shadow-ocean-water/25 hover:shadow-ocean-water/40 transition-shadow"
            >
              Try Checkout
            </Link>
            <Link
              href="/developers"
              className="rounded-xl border border-ocean-foam/20 px-8 py-3 text-sm font-semibold text-ocean-foam hover:bg-white/5 transition-colors"
            >
              View SDK
            </Link>
          </div>
        </div>
        {/* Wave separator */}
        <svg className="absolute bottom-0 left-0 w-full" viewBox="0 0 1440 80" fill="none" preserveAspectRatio="none">
          <path d="M0,40 C360,80 720,0 1080,40 C1260,60 1380,50 1440,40 L1440,80 L0,80 Z" fill="#F7FBFF" />
        </svg>
      </section>

      {/* Stats */}
      <section className="py-16">
        <div className="mx-auto max-w-6xl px-6">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            {STATS.map((stat) => (
              <div key={stat.label} className="text-center">
                <p className="text-3xl font-bold text-ocean-water">{stat.value}</p>
                <p className="mt-1 text-sm text-ocean-ink">{stat.label}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 bg-white">
        <div className="mx-auto max-w-6xl px-6">
          <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">Features</p>
          <h2 className="text-3xl md:text-4xl font-bold text-ocean-deep mb-12">
            Everything you need to accept onchain payments
          </h2>
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            {FEATURES.map((f) => (
              <div
                key={f.title}
                className="rounded-2xl border border-ocean-foam/20 p-6 hover:shadow-md hover:-translate-y-0.5 transition-all"
              >
                <h3 className="text-lg font-semibold text-ocean-deep mb-2">{f.title}</h3>
                <p className="text-sm text-ocean-ink leading-relaxed">{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Code Preview */}
      <section className="py-20 bg-ocean-deep">
        <div className="mx-auto max-w-6xl px-6 grid md:grid-cols-2 gap-12 items-center">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">Developer Experience</p>
            <h2 className="text-3xl font-bold text-white mb-4">
              Integrate in minutes, not weeks
            </h2>
            <p className="text-ocean-foam/60 leading-relaxed">
              Four lines to accept a payment. TypeScript SDK with full type safety,
              React hooks for state management, and drop-in components for instant checkout.
            </p>
            <Link
              href="/developers"
              className="mt-6 inline-block text-sm text-ocean-sui hover:text-ocean-sky transition-colors"
            >
              See all examples &rarr;
            </Link>
          </div>
          <div className="rounded-xl bg-ocean-midnight border border-ocean-ink/30 p-6 overflow-auto">
            <pre className="text-sm text-ocean-sky font-mono leading-relaxed whitespace-pre">
{`import { BaleenPay } from '@baleenpay/sdk'

const fs = new BaleenPay({
  network: 'testnet',
  packageId: '0xe0eb...306b32a',
  merchantId: '0x4db0...c17c24',
})

const { tx } = await fs.pay({
  amount: 49_000_000n,
  coin: 'USDC',
  orderId: 'order_001',
}, sender)`}
            </pre>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20">
        <div className="mx-auto max-w-2xl px-6 text-center">
          <h2 className="text-3xl font-bold text-ocean-deep mb-4">Ready to try it?</h2>
          <p className="text-ocean-ink mb-8">
            Experience a real checkout flow on SUI testnet. No credit card, no KYC — just connect a wallet.
          </p>
          <Link
            href="/checkout"
            className="rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal px-10 py-3.5 text-sm font-semibold text-white shadow-lg shadow-ocean-water/25 hover:shadow-ocean-water/40 transition-shadow"
          >
            Start Checkout Demo
          </Link>
        </div>
      </section>
    </>
  )
}
```

- [ ] **Step 3: Typecheck + visual verification**

```bash
pnpm --filter @baleenpay/demo typecheck
```

Expected: PASS. Check dev server — landing page renders with hero, stats, features, code preview, CTA.

- [ ] **Step 4: Commit**

```bash
git add apps/demo/app/page.tsx apps/demo/lib/snippets.ts
git commit -m "feat(demo): landing page — hero, stats, features, code preview, CTA"
```

---

## Task 5: Checkout Page (One-Time Payment)

**Files:**
- Create: `apps/demo/lib/products.ts`
- Create: `apps/demo/components/ProductCard.tsx`
- Create: `apps/demo/app/checkout/page.tsx`

### Steps

- [ ] **Step 1: Create `apps/demo/lib/products.ts`**

```ts
export interface Product {
  id: string
  name: string
  description: string
  priceUsd: number
}

export const DEMO_PRODUCTS: Product[] = [
  { id: 'basic', name: 'Basic', description: 'Essential features for small projects', priceUsd: 19 },
  { id: 'pro', name: 'Pro', description: 'Advanced features for growing teams', priceUsd: 49 },
  { id: 'enterprise', name: 'Enterprise', description: 'Full platform access with priority support', priceUsd: 149 },
]

export interface Plan {
  id: string
  name: string
  pricePerMonth: number
  periods: number
  badge?: string
}

export const DEMO_PLANS: Plan[] = [
  { id: 'monthly', name: 'Monthly', pricePerMonth: 49, periods: 1 },
  { id: 'annual', name: 'Annual', pricePerMonth: 39, periods: 12, badge: 'Save 20%' },
]

/**
 * Convert USD price to coin amount in smallest unit.
 * For demo: 1 USD = 1_000_000 USDC (6 decimals), 1 USD = 1_000_000_000 SUI (9 decimals, assuming 1:1 for testnet).
 */
export function priceToAmount(priceUsd: number, coin: string): bigint {
  const decimals = coin === 'USDC' ? 6 : 9
  return BigInt(priceUsd) * 10n ** BigInt(decimals)
}
```

- [ ] **Step 2: Create `apps/demo/components/ProductCard.tsx`**

```tsx
import type { Product } from '@/lib/products'

interface ProductCardProps {
  product: Product
  selected: boolean
  onSelect: () => void
}

export function ProductCard({ product, selected, onSelect }: ProductCardProps) {
  return (
    <button
      onClick={onSelect}
      className={`w-full rounded-2xl border p-6 text-left transition-all ${
        selected
          ? 'border-ocean-water bg-ocean-mist shadow-md ring-2 ring-ocean-water/30'
          : 'border-ocean-foam/30 bg-white hover:border-ocean-foam hover:shadow-sm'
      }`}
    >
      <h3 className="text-lg font-semibold text-ocean-deep">{product.name}</h3>
      <p className="mt-1 text-sm text-ocean-ink">{product.description}</p>
      <p className="mt-3 text-2xl font-bold text-ocean-water">${product.priceUsd}</p>
    </button>
  )
}
```

- [ ] **Step 3: Create `apps/demo/app/checkout/page.tsx`**

```tsx
'use client'

import { useState } from 'react'
import { usePayment } from '@baleenpay/react'
import { WalletGuard } from '@/components/WalletGuard'
import { TxStatus } from '@/components/TxStatus'
import { CoinToggle, coinDecimals } from '@/components/CoinToggle'
import { ProductCard } from '@/components/ProductCard'
import { DEMO_PRODUCTS, priceToAmount } from '@/lib/products'

export default function CheckoutPage() {
  const [selectedId, setSelectedId] = useState('pro')
  const [coin, setCoin] = useState('USDC')
  const { pay, status, error, result, reset } = usePayment()

  const product = DEMO_PRODUCTS.find((p) => p.id === selectedId)!
  const amount = priceToAmount(product.priceUsd, coin)

  const handlePay = () => {
    pay({
      amount,
      coin,
      orderId: `demo_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    })
  }

  return (
    <div className="mx-auto max-w-2xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Checkout Demo
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-8">
        Choose a plan and pay
      </h1>

      {/* Product Selection */}
      <div className="grid gap-4 mb-8">
        {DEMO_PRODUCTS.map((p) => (
          <ProductCard
            key={p.id}
            product={p}
            selected={p.id === selectedId}
            onSelect={() => { setSelectedId(p.id); reset() }}
          />
        ))}
      </div>

      <WalletGuard>
        {/* Checkout Card */}
        <div className="rounded-2xl border border-ocean-foam/30 bg-white p-8 shadow-sm">
          <h2 className="text-xl font-semibold text-ocean-deep mb-6">Order Summary</h2>

          <div className="flex items-center justify-between mb-4">
            <span className="text-ocean-ink">{product.name}</span>
            <span className="text-lg font-bold text-ocean-deep">${product.priceUsd}</span>
          </div>

          <div className="flex items-center justify-between mb-6">
            <span className="text-sm text-ocean-ink">Pay with</span>
            <CoinToggle value={coin} onChange={(c) => { setCoin(c); reset() }} />
          </div>

          <div className="border-t border-ocean-foam/30 pt-4 mb-6">
            <div className="flex items-center justify-between">
              <span className="text-sm text-ocean-ink">Network</span>
              <span className="rounded-full bg-ocean-mist px-3 py-0.5 text-xs font-medium text-ocean-water">
                SUI Testnet
              </span>
            </div>
          </div>

          <button
            onClick={handlePay}
            disabled={status !== 'idle' && status !== 'error' && status !== 'rejected'}
            className="w-full rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal py-3.5 text-sm font-semibold text-white shadow-lg shadow-ocean-water/25 hover:shadow-ocean-water/40 transition-shadow disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Pay ${product.priceUsd} with {coin}
          </button>

          <TxStatus status={status} error={error} digest={result} onReset={reset} />
        </div>
      </WalletGuard>
    </div>
  )
}
```

- [ ] **Step 4: Typecheck**

```bash
pnpm --filter @baleenpay/demo typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/demo/lib/products.ts apps/demo/components/ProductCard.tsx apps/demo/app/checkout/
git commit -m "feat(demo): checkout page — product selection, coin toggle, pay flow"
```

---

## Task 6: Subscribe Page

**Files:**
- Create: `apps/demo/components/PlanCard.tsx`
- Create: `apps/demo/app/subscribe/page.tsx`

### Steps

- [ ] **Step 1: Create `apps/demo/components/PlanCard.tsx`**

```tsx
import type { Plan } from '@/lib/products'

interface PlanCardProps {
  plan: Plan
  selected: boolean
  onSelect: () => void
}

export function PlanCard({ plan, selected, onSelect }: PlanCardProps) {
  return (
    <button
      onClick={onSelect}
      className={`relative w-full rounded-2xl border p-6 text-left transition-all ${
        selected
          ? 'border-ocean-water bg-ocean-mist shadow-md ring-2 ring-ocean-water/30'
          : 'border-ocean-foam/30 bg-white hover:border-ocean-foam hover:shadow-sm'
      }`}
    >
      {plan.badge && (
        <span className="absolute -top-3 right-4 rounded-full bg-ocean-sui px-3 py-0.5 text-xs font-semibold text-white">
          {plan.badge}
        </span>
      )}
      <h3 className="text-lg font-semibold text-ocean-deep">{plan.name}</h3>
      <p className="mt-2">
        <span className="text-2xl font-bold text-ocean-water">${plan.pricePerMonth}</span>
        <span className="text-sm text-ocean-ink">/month</span>
      </p>
      <p className="mt-1 text-sm text-ocean-ink">
        {plan.periods === 1 ? 'Billed monthly' : `${plan.periods} months prepaid — $${plan.pricePerMonth * plan.periods} total`}
      </p>
    </button>
  )
}
```

- [ ] **Step 2: Create `apps/demo/app/subscribe/page.tsx`**

```tsx
'use client'

import { useState } from 'react'
import { useSubscription } from '@baleenpay/react'
import { WalletGuard } from '@/components/WalletGuard'
import { TxStatus } from '@/components/TxStatus'
import { CoinToggle } from '@/components/CoinToggle'
import { PlanCard } from '@/components/PlanCard'
import { DEMO_PLANS, priceToAmount } from '@/lib/products'

const PERIOD_MS = 30 * 24 * 60 * 60 * 1000 // 30 days

export default function SubscribePage() {
  const [selectedId, setSelectedId] = useState('monthly')
  const [coin, setCoin] = useState('USDC')
  const { subscribe, cancel, fund, status, error, result, reset } = useSubscription()

  const plan = DEMO_PLANS.find((p) => p.id === selectedId)!
  const amountPerPeriod = priceToAmount(plan.pricePerMonth, coin)
  const total = plan.pricePerMonth * plan.periods

  const handleSubscribe = () => {
    subscribe({
      amountPerPeriod,
      periodMs: PERIOD_MS,
      prepaidPeriods: plan.periods,
      coin,
      orderId: `sub_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    })
  }

  return (
    <div className="mx-auto max-w-2xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Subscribe Demo
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-8">
        Choose a subscription plan
      </h1>

      {/* Plan Selection */}
      <div className="grid md:grid-cols-2 gap-4 mb-8">
        {DEMO_PLANS.map((p) => (
          <PlanCard
            key={p.id}
            plan={p}
            selected={p.id === selectedId}
            onSelect={() => { setSelectedId(p.id); reset() }}
          />
        ))}
      </div>

      <WalletGuard>
        {/* Subscription Card */}
        <div className="rounded-2xl border border-ocean-foam/30 bg-white p-8 shadow-sm">
          <h2 className="text-xl font-semibold text-ocean-deep mb-6">Subscription Summary</h2>

          <div className="space-y-3 mb-6">
            <div className="flex justify-between">
              <span className="text-ocean-ink">Plan</span>
              <span className="font-medium text-ocean-deep">{plan.name}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-ocean-ink">Per period</span>
              <span className="font-medium text-ocean-deep">${plan.pricePerMonth}/mo</span>
            </div>
            <div className="flex justify-between">
              <span className="text-ocean-ink">Prepaid periods</span>
              <span className="font-medium text-ocean-deep">{plan.periods} month{plan.periods > 1 ? 's' : ''}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-ocean-ink">Pay with</span>
              <CoinToggle value={coin} onChange={(c) => { setCoin(c); reset() }} />
            </div>
          </div>

          <div className="border-t border-ocean-foam/30 pt-4 mb-6">
            <div className="flex justify-between">
              <span className="font-semibold text-ocean-deep">Total upfront</span>
              <span className="text-xl font-bold text-ocean-water">${total}</span>
            </div>
          </div>

          <button
            onClick={handleSubscribe}
            disabled={status !== 'idle' && status !== 'error' && status !== 'rejected'}
            className="w-full rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal py-3.5 text-sm font-semibold text-white shadow-lg shadow-ocean-water/25 hover:shadow-ocean-water/40 transition-shadow disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Subscribe — ${total} with {coin}
          </button>

          <TxStatus status={status} error={error} digest={result} onReset={reset} />

          {status === 'success' && result && (
            <div className="mt-6 rounded-xl bg-emerald-50 border border-emerald-200 p-4">
              <p className="text-sm font-medium text-emerald-700 mb-2">Subscription Active</p>
              <p className="text-xs text-emerald-600">
                Your subscription is live on SUI testnet. In production, the merchant
                can process payments each period automatically.
              </p>
            </div>
          )}
        </div>
      </WalletGuard>
    </div>
  )
}
```

- [ ] **Step 3: Typecheck**

```bash
pnpm --filter @baleenpay/demo typecheck
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/demo/components/PlanCard.tsx apps/demo/app/subscribe/
git commit -m "feat(demo): subscribe page — plan selection, subscription flow"
```

---

## Task 7: Dashboard Page (Merchant View)

**Files:**
- Create: `apps/demo/components/StatCard.tsx`
- Create: `apps/demo/components/PaymentTable.tsx`
- Create: `apps/demo/app/dashboard/page.tsx`

### Steps

- [ ] **Step 1: Create `apps/demo/components/StatCard.tsx`**

```tsx
interface StatCardProps {
  label: string
  value: string
  sub?: string
}

export function StatCard({ label, value, sub }: StatCardProps) {
  return (
    <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
      <p className="text-sm text-ocean-ink mb-1">{label}</p>
      <p className="text-2xl font-bold text-ocean-deep">{value}</p>
      {sub && <p className="text-xs text-ocean-ink mt-1">{sub}</p>}
    </div>
  )
}
```

- [ ] **Step 2: Create `apps/demo/components/PaymentTable.tsx`**

```tsx
import type { BaleenPayEventData } from '@baleenpay/sdk'
import { truncateAddress, formatAmount, formatDate } from '@/lib/format'
import { SUISCAN_URL } from '@/lib/config'

interface PaymentTableProps {
  events: BaleenPayEventData[]
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
```

- [ ] **Step 3: Create `apps/demo/app/dashboard/page.tsx`**

```tsx
'use client'

import { useMerchant, usePaymentHistory } from '@baleenpay/react'
import { useDAppKit, useCurrentAccount } from '@mysten/dapp-kit-react'
import { buildClaimYield, buildSelfPause, buildSelfUnpause } from '@baleenpay/sdk'
import { useState } from 'react'
import { WalletGuard } from '@/components/WalletGuard'
import { TxStatus } from '@/components/TxStatus'
import { StatCard } from '@/components/StatCard'
import { PaymentTable } from '@/components/PaymentTable'
import { DEMO_CONFIG, MERCHANT_CAP_ID } from '@/lib/config'
import { formatAmount } from '@/lib/format'
import type { MutationStatus } from '@baleenpay/react'

export default function DashboardPage() {
  const account = useCurrentAccount()
  const dAppKit = useDAppKit()
  const { merchant, isLoading: merchantLoading, refetch: refetchMerchant } = useMerchant()
  const { events, isLoading: historyLoading, hasNextPage, fetchNextPage } = usePaymentHistory()

  // Admin action state
  const [actionStatus, setActionStatus] = useState<MutationStatus>('idle')
  const [actionError, setActionError] = useState<Error | null>(null)
  const [actionDigest, setActionDigest] = useState<string | null>(null)

  const resetAction = () => {
    setActionStatus('idle')
    setActionError(null)
    setActionDigest(null)
  }

  const executeAdminTx = async (buildFn: () => import('@mysten/sui/transactions').Transaction) => {
    try {
      resetAction()
      setActionStatus('signing')
      const tx = buildFn()
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      if (result.FailedTransaction) {
        throw new Error(result.FailedTransaction.status.error?.message ?? 'Transaction failed')
      }
      setActionDigest(result.Transaction.digest)
      setActionStatus('success')
      refetchMerchant()
    } catch (err) {
      const e = err instanceof Error ? err : new Error(String(err))
      setActionError(e)
      setActionStatus(e.message.toLowerCase().includes('reject') ? 'rejected' : 'error')
    }
  }

  return (
    <div className="mx-auto max-w-5xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Merchant Dashboard
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-8">
        Dashboard
      </h1>

      <WalletGuard>
        {merchantLoading ? (
          <p className="text-ocean-ink">Loading merchant data...</p>
        ) : !merchant ? (
          <div className="rounded-2xl border border-ocean-foam/30 bg-white p-12 text-center">
            <p className="text-ocean-ink">No merchant account found</p>
            <p className="text-sm text-ocean-ink/60 mt-1">
              The connected wallet does not own a MerchantCap for this demo merchant.
            </p>
          </div>
        ) : (
          <>
            {/* Merchant Header */}
            <div className="flex items-center gap-3 mb-8">
              <h2 className="text-xl font-semibold text-ocean-deep">{merchant.brandName}</h2>
              {merchant.paused && (
                <span className="rounded-full bg-amber-100 px-3 py-0.5 text-xs font-semibold text-amber-700">
                  Paused
                </span>
              )}
            </div>

            {/* Stats Grid */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
              <StatCard
                label="Total Received"
                value={formatAmount(merchant.totalReceived)}
                sub="MIST"
              />
              <StatCard
                label="Idle Principal"
                value={formatAmount(merchant.idlePrincipal)}
                sub="In escrow"
              />
              <StatCard
                label="Accrued Yield"
                value={formatAmount(merchant.accruedYield)}
                sub="Claimable"
              />
              <StatCard
                label="Active Subscriptions"
                value={String(merchant.activeSubscriptions)}
              />
            </div>

            {/* Admin Actions */}
            <div className="grid md:grid-cols-2 gap-4 mb-8">
              {/* Yield Card */}
              <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
                <h3 className="text-lg font-semibold text-ocean-deep mb-2">Claim Yield</h3>
                <p className="text-sm text-ocean-ink mb-4">
                  Accrued: {formatAmount(merchant.accruedYield)} MIST
                </p>
                <button
                  onClick={() => executeAdminTx(() => buildClaimYield(DEMO_CONFIG, MERCHANT_CAP_ID))}
                  disabled={merchant.accruedYield === 0n || (actionStatus !== 'idle' && actionStatus !== 'error' && actionStatus !== 'rejected')}
                  className="rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal px-6 py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Claim Yield
                </button>
              </div>

              {/* Pause Toggle */}
              <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
                <h3 className="text-lg font-semibold text-ocean-deep mb-2">Merchant Status</h3>
                <p className="text-sm text-ocean-ink mb-4">
                  {merchant.paused ? 'Merchant is paused — no payments accepted' : 'Merchant is active'}
                </p>
                <button
                  onClick={() =>
                    executeAdminTx(() =>
                      merchant.paused
                        ? buildSelfUnpause(DEMO_CONFIG, MERCHANT_CAP_ID)
                        : buildSelfPause(DEMO_CONFIG, MERCHANT_CAP_ID)
                    )
                  }
                  disabled={actionStatus !== 'idle' && actionStatus !== 'error' && actionStatus !== 'rejected'}
                  className={`rounded-xl px-6 py-2.5 text-sm font-semibold shadow-md disabled:opacity-50 disabled:cursor-not-allowed ${
                    merchant.paused
                      ? 'bg-emerald-500 text-white'
                      : 'bg-amber-500 text-white'
                  }`}
                >
                  {merchant.paused ? 'Unpause' : 'Pause'}
                </button>
              </div>
            </div>

            <TxStatus status={actionStatus} error={actionError} digest={actionDigest} onReset={resetAction} />

            {/* Payment History */}
            <div className="mt-8">
              <h3 className="text-lg font-semibold text-ocean-deep mb-4">Payment History</h3>
              <PaymentTable
                events={events}
                isLoading={historyLoading}
                hasNextPage={hasNextPage}
                onLoadMore={fetchNextPage}
              />
            </div>
          </>
        )}
      </WalletGuard>
    </div>
  )
}
```

- [ ] **Step 4: Typecheck**

```bash
pnpm --filter @baleenpay/demo typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/demo/components/StatCard.tsx apps/demo/components/PaymentTable.tsx apps/demo/app/dashboard/
git commit -m "feat(demo): dashboard page — merchant stats, yield, pause, payment history"
```

---

## Task 8: Developers Page (Code Snippets)

**Files:**
- Create: `apps/demo/components/CodeSnippet.tsx`
- Modify: `apps/demo/lib/snippets.ts` (add all developer snippets)
- Create: `apps/demo/app/developers/page.tsx`

### Steps

- [ ] **Step 1: Create `apps/demo/components/CodeSnippet.tsx`**

```tsx
'use client'

import { useState } from 'react'

interface CodeSnippetProps {
  title: string
  description: string
  code: string
  language?: string
}

export function CodeSnippet({ title, description, code, language = 'TypeScript' }: CodeSnippetProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="rounded-2xl border border-ocean-foam/20 bg-white overflow-hidden">
      <div className="flex items-center justify-between px-6 py-4 border-b border-ocean-foam/20">
        <div>
          <h3 className="text-lg font-semibold text-ocean-deep">{title}</h3>
          <p className="text-sm text-ocean-ink mt-0.5">{description}</p>
        </div>
        <div className="flex items-center gap-3">
          <span className="rounded-full bg-ocean-mist px-3 py-0.5 text-xs font-medium text-ocean-water">
            {language}
          </span>
          <button
            onClick={handleCopy}
            className="rounded-lg border border-ocean-foam/30 px-3 py-1.5 text-xs font-medium text-ocean-ink hover:bg-ocean-mist transition-colors"
          >
            {copied ? 'Copied!' : 'Copy'}
          </button>
        </div>
      </div>
      <div className="bg-ocean-deep p-6 overflow-auto">
        <pre className="text-sm text-ocean-sky font-mono leading-relaxed whitespace-pre">{code}</pre>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Update `apps/demo/lib/snippets.ts`** with all developer snippets

Replace the file contents:

```ts
export interface Snippet {
  title: string
  description: string
  code: string
}

export const DEVELOPER_SNIPPETS: Snippet[] = [
  {
    title: 'Quick Start',
    description: 'Initialize the SDK with your testnet config',
    code: `import { BaleenPay } from '@baleenpay/sdk'

const fs = new BaleenPay({
  network: 'testnet',
  packageId: '0xe0eb...306b32a',
  merchantId: '0x4db0...c17c24',
})`,
  },
  {
    title: 'Accept a Payment',
    description: 'Build and execute a one-time payment transaction',
    code: `const { tx } = await fs.pay({
  amount: 49_000_000n,   // 49 USDC (6 decimals)
  coin: 'USDC',
  orderId: 'order_001',  // dedup key
}, senderAddress)

// Sign with wallet adapter
const result = await wallet.signAndExecuteTransaction({ transaction: tx })`,
  },
  {
    title: 'Create a Subscription',
    description: 'Set up a recurring payment with prepaid periods',
    code: `const { tx } = await fs.subscribe({
  amountPerPeriod: 49_000_000n,
  periodMs: 30 * 24 * 60 * 60 * 1000, // 30 days
  prepaidPeriods: 3,
  coin: 'USDC',
  orderId: 'sub_001',
}, senderAddress)`,
  },
  {
    title: 'React Hook — usePayment',
    description: 'State-managed payment flow in a React component',
    code: `import { usePayment } from '@baleenpay/react'

function CheckoutButton() {
  const { pay, status, error, result, reset } = usePayment()

  return (
    <button
      onClick={() => pay({ amount: 49_000_000n, coin: 'USDC', orderId: 'order_001' })}
      disabled={status !== 'idle'}
    >
      {status === 'signing' ? 'Confirm in wallet...' : 'Pay $49'}
    </button>
  )
}`,
  },
  {
    title: 'Drop-in Component',
    description: 'One-line checkout button with built-in state management',
    code: `import { CheckoutButton } from '@baleenpay/react'

<CheckoutButton
  amount={49_000_000n}
  coin="USDC"
  orderId="order_001"
  onSuccess={(digest) => console.log('Paid!', digest)}
  onError={(err) => console.error(err)}
/>`,
  },
  {
    title: 'Query Merchant Data',
    description: 'Read on-chain merchant state and payment history',
    code: `// SDK client
const merchant = await fs.getMerchant()
console.log(merchant.totalReceived)  // bigint
console.log(merchant.accruedYield)   // bigint
console.log(merchant.paused)         // boolean

// React hook
const { merchant, isLoading } = useMerchant()
const { events, hasNextPage, fetchNextPage } = usePaymentHistory()`,
  },
]
```

- [ ] **Step 3: Create `apps/demo/app/developers/page.tsx`**

```tsx
import { CodeSnippet } from '@/components/CodeSnippet'
import { DEVELOPER_SNIPPETS } from '@/lib/snippets'

export default function DevelopersPage() {
  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Developer Guide
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-4">
        Integrate BaleenPay in minutes
      </h1>
      <p className="text-ocean-ink mb-12 max-w-xl">
        TypeScript SDK with React hooks and drop-in components.
        Same patterns you know from Stripe — built for SUI.
      </p>

      <div className="space-y-8">
        {DEVELOPER_SNIPPETS.map((snippet) => (
          <CodeSnippet
            key={snippet.title}
            title={snippet.title}
            description={snippet.description}
            code={snippet.code}
          />
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Typecheck**

```bash
pnpm --filter @baleenpay/demo typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/demo/components/CodeSnippet.tsx apps/demo/lib/snippets.ts apps/demo/app/developers/
git commit -m "feat(demo): developers page — 6 code snippet cards with copy"
```

---

## Task 9: Build Verification + Final Polish

**Files:**
- Potentially modify any file for type/build fixes

### Steps

- [ ] **Step 1: Build all workspace packages**

```bash
cd /Users/ramonliao/Documents/Code/Project/Web3/BlockchainDev/SUI/Projects/BaleenPay
pnpm --filter @baleenpay/sdk build
pnpm --filter @baleenpay/react build
pnpm --filter @baleenpay/demo build
```

Expected: All three builds succeed. Fix any type errors or import issues discovered during `next build`.

- [ ] **Step 2: Verify existing SDK + React tests still pass**

```bash
pnpm --filter @baleenpay/sdk test
pnpm --filter @baleenpay/react test
```

Expected: 153/153 SDK tests PASS, 70/70 React tests PASS. No regressions.

- [ ] **Step 3: Start dev server and manually verify all pages**

```bash
pnpm --filter @baleenpay/demo dev
```

Verify checklist:
- [ ] Landing page: hero, stats, features, code preview, CTA all render
- [ ] Nav: sticky, links work, transparent→white on scroll
- [ ] `/checkout`: products display, selection works, coin toggle works, WalletGuard shows connect prompt
- [ ] `/subscribe`: plans display, badge on Annual, coin toggle works
- [ ] `/dashboard`: WalletGuard, merchant data loads (or "no merchant" message)
- [ ] `/developers`: 6 code snippets render, copy button works
- [ ] Footer renders on all pages

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(demo): build verification + polish"
```

---

## Summary

| Task | Description | Components |
|------|-------------|------------|
| 1 | Scaffold + Providers | package.json, next.config, tsconfig, tailwind, layout, config |
| 2 | Nav + Footer + Format Helpers | Nav.tsx, Footer.tsx, format.ts |
| 3 | Shared Components | WalletGuard, TxStatus, CoinToggle |
| 4 | Landing Page | page.tsx (hero, stats, features, code preview, CTA) |
| 5 | Checkout Page | ProductCard, checkout/page.tsx |
| 6 | Subscribe Page | PlanCard, subscribe/page.tsx |
| 7 | Dashboard Page | StatCard, PaymentTable, dashboard/page.tsx |
| 8 | Developers Page | CodeSnippet, snippets.ts, developers/page.tsx |
| 9 | Build Verification | Full build + test regression + manual QA |

**Estimated commits:** 9
**Dependency chain:** Task 1 → Task 2 → Task 3 (shared deps) → Tasks 4-8 (pages, partially parallelizable: 4∥8, 5∥6, 7 after 3) → Task 9 (verification)
