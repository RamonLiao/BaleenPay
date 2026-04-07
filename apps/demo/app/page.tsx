import Link from 'next/link'

const PAIN_POINTS = [
  {
    icon: '💸',
    title: 'Payment Float Earns Nothing',
    desc: 'SaaS platforms collect recurring revenue, but funds sit idle in wallets between collection and withdrawal — dead capital.',
  },
  {
    icon: '⏳',
    title: 'Slow Settlement, High Fees',
    desc: 'Traditional payment rails take 2-7 days to settle with 2.9% + $0.30 per transaction. Cross-border is worse.',
  },
  {
    icon: '🔧',
    title: 'Crypto Payments Are Hard',
    desc: 'Building payment flows on-chain means wrestling with wallets, transactions, subscriptions, and yield protocols from scratch.',
  },
]

const HOW_IT_WORKS = [
  {
    step: '01',
    title: 'Customer Pays',
    desc: 'USDC payment via embedded checkout widget. Sub-second finality on SUI.',
  },
  {
    step: '02',
    title: 'Auto-Route to Yield',
    desc: 'Funds are automatically deposited into StableLayer yield aggregator. No manual treasury management.',
  },
  {
    step: '03',
    title: 'Earn While Idle',
    desc: 'Payment float continuously earns yield. Merchants claim accumulated returns anytime from dashboard.',
  },
]

const FEATURES = [
  { title: 'One-Time Payments', desc: 'Order ID deduplication, instant settlement, multi-coin support.' },
  { title: 'Recurring Subscriptions', desc: 'Prepaid periods, auto-processing, pause & cancel built-in.' },
  { title: 'Auto Yield Routing', desc: 'Idle funds earn yield via StableLayer. No config needed.' },
  { title: 'Merchant Dashboard', desc: 'Track revenue, monitor yield accumulation, claim earnings.' },
  { title: 'Stripe-like SDK', desc: 'TypeScript SDK + React hooks. 4 lines to accept a payment.' },
  { title: 'Admin Controls', desc: 'Self-pause, admin freeze, dual-pause model for compliance.' },
]

const STATS = [
  { value: '<1s', label: 'Settlement' },
  { value: '~$0.001', label: 'Per Transaction' },
  { value: '24/7', label: 'Yield Accrual' },
  { value: '100%', label: 'On-Chain' },
]

export default function LandingPage() {
  return (
    <>
      {/* Hero */}
      <section className="relative overflow-hidden bg-gradient-to-br from-ocean-deep via-ocean-midnight to-ocean-deep py-32">
        <div className="absolute top-0 right-0 w-[600px] h-[600px] rounded-full bg-ocean-water/5 blur-3xl" />
        <div className="absolute bottom-0 left-0 w-[400px] h-[400px] rounded-full bg-ocean-teal/5 blur-3xl" />
        <div className="relative mx-auto max-w-6xl px-6 text-center">
          <div className="inline-flex items-center gap-2 rounded-full border border-ocean-sui/30 bg-ocean-sui/10 px-4 py-1.5 mb-6">
            <span className="h-1.5 w-1.5 rounded-full bg-ocean-sui animate-pulse" />
            <span className="text-xs font-medium text-ocean-sui">Built on SUI</span>
          </div>
          <h1 className="text-5xl md:text-6xl font-bold text-white tracking-tight leading-tight">
            Your payment float<br />
            should be <span className="text-transparent bg-clip-text bg-gradient-to-r from-ocean-sui to-ocean-teal">earning yield</span>
          </h1>
          <p className="mt-6 text-lg text-ocean-foam/70 max-w-2xl mx-auto leading-relaxed">
            BaleenPay intercepts idle SaaS revenue and auto-routes it through DeFi yield protocols.
            Accept stablecoin payments. Earn yield on float. Claim anytime.
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

      {/* Problem */}
      <section className="py-20 bg-white">
        <div className="mx-auto max-w-6xl px-6">
          <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">The Problem</p>
          <h2 className="text-3xl md:text-4xl font-bold text-ocean-deep mb-4">
            SaaS revenue is sitting idle
          </h2>
          <p className="text-ocean-ink max-w-2xl mb-12 leading-relaxed">
            Every SaaS platform collects payments before delivering services — subscriptions, prepaid plans, deposits.
            That &ldquo;payment float&rdquo; is dead capital. BaleenPay turns it into a revenue stream.
          </p>
          <div className="grid md:grid-cols-3 gap-6">
            {PAIN_POINTS.map((p) => (
              <div
                key={p.title}
                className="rounded-2xl border border-red-100 bg-red-50/50 p-6"
              >
                <span className="text-2xl">{p.icon}</span>
                <h3 className="mt-3 text-lg font-semibold text-ocean-deep">{p.title}</h3>
                <p className="mt-2 text-sm text-ocean-ink leading-relaxed">{p.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-20 bg-ocean-surface">
        <div className="mx-auto max-w-6xl px-6">
          <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">How It Works</p>
          <h2 className="text-3xl md:text-4xl font-bold text-ocean-deep mb-12">
            From payment to yield in one flow
          </h2>
          <div className="grid md:grid-cols-3 gap-8">
            {HOW_IT_WORKS.map((item, i) => (
              <div key={item.step} className="relative">
                {i < HOW_IT_WORKS.length - 1 && (
                  <div className="hidden md:block absolute top-8 left-full w-full h-px border-t-2 border-dashed border-ocean-foam -translate-x-4" />
                )}
                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-ocean-water to-ocean-teal text-white text-xl font-bold shadow-lg shadow-ocean-water/20">
                  {item.step}
                </div>
                <h3 className="mt-4 text-lg font-semibold text-ocean-deep">{item.title}</h3>
                <p className="mt-2 text-sm text-ocean-ink leading-relaxed">{item.desc}</p>
              </div>
            ))}
          </div>

          {/* Flow Diagram */}
          <div className="mt-16 rounded-2xl border border-ocean-foam/40 bg-white p-8 overflow-x-auto">
            <div className="flex items-center justify-between min-w-[600px] gap-4">
              {[
                { label: 'Customer', sub: 'Pays USDC' },
                { label: 'BaleenPay', sub: 'Smart Contract' },
                { label: 'StableLayer', sub: 'Yield Aggregator' },
                { label: 'Merchant', sub: 'Claims Yield' },
              ].map((node, i, arr) => (
                <div key={node.label} className="flex items-center gap-4">
                  <div className="flex flex-col items-center">
                    <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-ocean-mist">
                      <span className="text-sm font-bold text-ocean-water">
                        {node.label.charAt(0)}
                      </span>
                    </div>
                    <p className="mt-2 text-sm font-semibold text-ocean-deep">{node.label}</p>
                    <p className="text-xs text-ocean-ink">{node.sub}</p>
                  </div>
                  {i < arr.length - 1 && (
                    <svg className="h-4 w-8 flex-shrink-0 text-ocean-water" fill="none" viewBox="0 0 32 16">
                      <path d="M0 8h28m0 0l-6-6m6 6l-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  )}
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 bg-white">
        <div className="mx-auto max-w-6xl px-6">
          <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">Features</p>
          <h2 className="text-3xl md:text-4xl font-bold text-ocean-deep mb-12">
            Payment infrastructure that works for you
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

const bp = new BaleenPay({
  network: 'mainnet',
  packageId: '0xe0eb...306b32a',
  merchantId: '0x4db0...c17c24',
})

// Accept a one-time payment
const { tx } = await bp.pay({
  amount: 49_000_000n,
  coin: 'USDC',
  orderId: 'inv_2024_001',
}, sender)

// Check accumulated yield
const yield = await bp.getYieldInfo(merchantId)
// → { principal: 12500n, accumulated: 340n }`}
            </pre>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20">
        <div className="mx-auto max-w-2xl px-6 text-center">
          <h2 className="text-3xl font-bold text-ocean-deep mb-4">
            Stop leaving money on the table
          </h2>
          <p className="text-ocean-ink mb-8 leading-relaxed">
            Every dollar of payment float can be earning yield right now.
            Try the demo on SUI testnet — no credit card, no KYC.
          </p>
          <div className="flex items-center justify-center gap-4">
            <Link
              href="/checkout"
              className="rounded-xl bg-gradient-to-r from-ocean-water to-ocean-teal px-10 py-3.5 text-sm font-semibold text-white shadow-lg shadow-ocean-water/25 hover:shadow-ocean-water/40 transition-shadow"
            >
              Try Checkout Demo
            </Link>
            <Link
              href="/dashboard"
              className="rounded-xl border border-ocean-ink/20 px-10 py-3.5 text-sm font-semibold text-ocean-ink hover:bg-ocean-mist transition-colors"
            >
              View Dashboard
            </Link>
          </div>
        </div>
      </section>
    </>
  )
}
