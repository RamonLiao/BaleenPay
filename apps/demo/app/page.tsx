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
