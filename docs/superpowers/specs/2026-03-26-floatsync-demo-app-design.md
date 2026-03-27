# FloatSync Demo App — Design Spec

## 1. Purpose & Audience

**Primary audience:** Investors and potential partners evaluating FloatSync as a Web3 payment infrastructure play. They need to see a polished, working product — not a prototype.

**Secondary audience:** Developers already using Stripe who are curious about Web3 payments. They need to see that integrating FloatSync is as simple as Stripe.

**Core message:** "This is the Stripe of on-chain payments — and it works today."

## 2. Scope

### In Scope
- 5-page Next.js App Router application connected to SUI testnet
- Full wallet integration (real transactions, not mocked)
- One-time payments (`pay_once_v2`) and subscriptions (`subscribe_v2`)
- Merchant dashboard with yield, payment history, and self-pause
- Developer-facing code snippet showcase
- Ocean-themed visual design (Stripe structure × SUI color palette)

### Out of Scope
- Full documentation site (separate project)
- User auth / login (wallet address = identity)
- StableLayer yield integration (deferred, API not ready). Note: the contract already has `claim_yield` and yield accrual via the router module — what's deferred is the StableLayer *external* DeFi integration. Dashboard will show on-chain yield data that already exists.
- Mobile responsive (desktop-first MVP)
- i18n, dark mode, analytics charts (future upgrades — see `tasks/notes.md`)

## 3. Visual Design

### Color System — "Ocean Palette"

Inspired by SUI's identity: ocean, water, fluidity. Applied to Stripe's structural patterns (generous whitespace, card-based layouts, sticky nav, alternating light/dark sections).

| Token | Hex | Usage |
|-------|-----|-------|
| Deep Ocean | `#0B1426` | Dark sections bg, primary text |
| Midnight | `#0D2137` | Dark section variants |
| Sea Ink | `#1A3A5C` | Secondary dark text |
| Water Blue | `#2389E8` | Primary CTA, links |
| SUI Blue | `#4DA2FF` | Brand accent, badges |
| Teal Accent | `#0EA5E9` | Gradient endpoint, secondary accent |
| Sky Blue | `#6FBCFF` | Light accent, code syntax |
| Foam | `#B8DEFF` | Light badges, borders |
| Mist | `#E8F4FF` | Light section bg |
| Surface | `#F7FBFF` | Page background |
| White | `#FFFFFF` | Cards, inputs |

### Typography
- Font: Inter (system fallback: -apple-system, sans-serif)
- Hero: 56px/700, -1.5px tracking
- Section headings: 40px/700, -1px tracking
- Body: 16-18px/400, 1.6 line-height
- Code: SF Mono / Fira Code, 13px

### Key Visual Patterns
- SVG wave pattern at hero bottom (water/fluidity metaphor)
- Subtle radial gradient glow (top-right hero, simulates light on water)
- Cards: 16px radius, 1px border `rgba(77,162,255,0.08)`, subtle hover lift
- CTA buttons: `linear-gradient(135deg, Water Blue, Teal Accent)` with glow shadow
- Section label: 13px uppercase, SUI Blue, letter-spacing 1.5px (Stripe pattern)

## 4. Pages

### 4.1 Landing (`/`)

**Purpose:** First impression. Communicate value prop, build credibility, drive to checkout/subscribe.

**Sections (top to bottom):**

1. **Nav** — Sticky, transparent→white on scroll. Logo, page links, "Get Started" CTA
2. **Hero** — Headline: "Payments infrastructure for the onchain economy". Subtext + CTA buttons ("Start now" / "Read the docs"). SVG wave at bottom
3. **Stats bar** — 4 metrics: settlement time (<1s), tx cost ($0.001), multi-coin, on-chain transparency
4. **Features grid** — 6 cards (2×3): One-time Payments, Subscriptions, Yield, Admin Controls, Instant Settlement, Developer SDK
5. **Code preview** — Dark bg section. Left: marketing copy. Right: syntax-highlighted SDK code (4-line pay example)
6. **Checkout preview** — Light bg. Centered checkout card mockup showing the payment flow
7. **Footer** — Minimal, deep ocean bg

**Data:** Static content, no wallet needed.

### 4.2 Checkout (`/checkout`)

**Purpose:** Demonstrate one-time payment flow. Payer experience.

**Layout:** Centered checkout card (max-width ~480px), similar to Stripe Checkout.

**Flow:**
1. **Product selection** — 3 demo SaaS products (Basic $19, Pro $49, Enterprise $149) as selectable cards
2. **Coin selection** — SUI / USDC toggle badges
3. **Order summary** — Product, amount, coin, network fee estimate
4. **Wallet connection** — `ConnectButton` from dapp-kit if not connected
5. **Pay button** — "Pay $49 with USDC" → triggers `usePayment` hook
6. **State transitions** (driven by `MutationStatus`):
   - `idle` → button enabled
   - `building` → "Preparing..." spinner
   - `signing` → "Confirm in wallet..." (wallet popup)
   - `confirming` → "Confirming on SUI..." spinner
   - `success` → checkmark animation + tx digest link (to SuiScan)
   - `error` → error message + "Try again" button

**SDK integration:**
```tsx
const { pay, status, error, reset } = usePayment()
// onClick:
pay({ amount: 49_000_000n, coin: 'USDC', orderId: `demo_${Date.now()}` })
```

**Edge cases:**
- Wallet not connected → show connect prompt instead of pay button
- Insufficient balance → show error after tx failure
- Order ID dedup → auto-generate unique orderId per attempt

### 4.3 Subscribe (`/subscribe`)

**Purpose:** Demonstrate recurring payment flow. Payer experience.

**Layout:** Plan selection cards → subscription checkout card.

**Flow:**
1. **Plan selection** — 2 plans:
   - Monthly: $49/mo (1 period prepaid)
   - Annual: $39/mo (12 periods prepaid, "Save 20%" badge)
2. **Coin selection** — SUI / USDC toggle
3. **Summary** — Plan, amount per period, prepaid periods, total upfront, coin
4. **Connect wallet + Subscribe** → triggers `useSubscription.subscribe()`
5. **Success state** — Shows subscription details: next due date, balance remaining, subscription ID
6. **Post-subscribe actions** — "Fund more" button (→ `fund`), "Cancel" button (→ `cancel`)

**SDK integration:**
```tsx
const { subscribe, cancel, fund, status } = useSubscription()
// onClick:
subscribe({
  amountPerPeriod: 49_000_000n,
  periodMs: 30 * 24 * 60 * 60 * 1000,
  prepaidPeriods: 1,
  coin: 'USDC',
  orderId: `sub_${Date.now()}`,
})
```

### 4.4 Dashboard (`/dashboard`)

**Purpose:** Demonstrate merchant experience. Shows the "business owner" side.

**Layout:** Sidebar (or top tabs) + main content area.

**Requires:** Connected wallet that holds a MerchantCap (the testnet merchant we deployed).

**Sections:**

1. **Merchant header** — Brand name, merchant ID (truncated), paused status badge
2. **Stats cards** (grid of 4):
   - Total Received (from `MerchantInfo.totalReceived`)
   - Idle Principal (funds in escrow)
   - Accrued Yield (claimable)
   - Active Subscriptions (count)
3. **Yield card** — Larger card showing accrued yield + "Claim Yield" CTA button. Triggers `claimYield` tx
4. **Self-pause toggle** — Switch with confirmation. Triggers `selfPause` / `selfUnpause`. Shows paused state immediately
5. **Payment history table** — Paginated table from `usePaymentHistory`:
   - Columns: Time, Payer (truncated address), Amount, Coin, Order ID, Tx Digest (link)
   - Cursor-based pagination ("Load more" or infinite scroll)

**SDK integration:**
```tsx
// Read-only queries (React hooks)
const { merchant, isLoading } = useMerchant()
const { events, hasNextPage, fetchNextPage } = usePaymentHistory()

// Merchant mutations — no dedicated hook, use raw PTB builders + dapp-kit
import { buildClaimYield, buildSelfPause, buildSelfUnpause } from '@floatsync/sdk'
import { useDAppKit } from '@mysten/dapp-kit-react'

const dAppKit = useDAppKit()
// Claim yield (requires merchantCapId — resolve via getOwnedObjects filter on MerchantCap type):
const tx = buildClaimYield(config, merchantCapId)
await dAppKit.signAndExecuteTransaction({ transaction: tx })
// Self-pause / unpause:
const tx = buildSelfPause(config, merchantCapId)
await dAppKit.signAndExecuteTransaction({ transaction: tx })
```

**Note:** `useMerchant` is read-only. Merchant write operations (claim yield, pause/unpause) use SDK PTB builders directly with dapp-kit's `useSignAndExecuteTransaction`. This is intentional — these are infrequent admin actions that don't need the full state-machine treatment of `usePayment`/`useSubscription`.

**Edge cases:**
- No MerchantCap → show "Register Merchant" flow or info message
- No payments yet → empty state with illustration

### 4.5 Developers (`/developers`)

**Purpose:** Show developers how easy FloatSync is to integrate. Code-as-marketing.

**Layout:** Clean single-column with full-width code blocks.

**Sections (each is a code snippet card):**

1. **Quick Start** — SDK initialization (4 lines)
2. **Accept a Payment** — `pay()` call with orderId
3. **Create a Subscription** — `subscribe()` with plan params
4. **React Hook** — `usePayment()` in a component
5. **Drop-in Component** — `<CheckoutButton>` one-liner
6. **Query Merchant Data** — `getMerchant()` + `getPaymentHistory()`

**Each snippet card:**
- Title + 1-line description
- Syntax-highlighted code block (TypeScript)
- "Copy" button (top-right)
- Language tag badge

**No interactivity beyond copy.** This is a showcase, not a playground.

## 5. Architecture

### Directory Structure
```
apps/demo/
├── app/
│   ├── layout.tsx            # Providers: Wallet + QueryClient + FloatSync
│   ├── page.tsx              # Landing
│   ├── checkout/page.tsx
│   ├── subscribe/page.tsx
│   ├── dashboard/page.tsx
│   └── developers/page.tsx
├── components/
│   ├── layout/
│   │   ├── Nav.tsx
│   │   ├── Footer.tsx
│   │   └── WaveHero.tsx
│   ├── checkout/
│   │   ├── ProductSelector.tsx
│   │   ├── CoinToggle.tsx
│   │   ├── CheckoutCard.tsx
│   │   └── TxStatus.tsx
│   ├── subscribe/
│   │   ├── PlanCard.tsx
│   │   ├── SubscribeCard.tsx
│   │   └── SubscriptionStatus.tsx
│   ├── dashboard/
│   │   ├── StatCard.tsx
│   │   ├── YieldCard.tsx
│   │   ├── PauseToggle.tsx
│   │   └── PaymentTable.tsx
│   └── developers/
│   │   └── CodeSnippet.tsx
│   └── shared/
│       ├── WalletGuard.tsx    # Shows connect prompt if no wallet
│       └── CoinBadge.tsx
├── lib/
│   ├── config.ts             # Testnet config (packageId, merchantId)
│   ├── products.ts           # Demo product definitions
│   └── snippets.ts           # Code snippet strings for /developers
├── public/
│   └── og-image.png
├── tailwind.config.ts
├── next.config.ts
├── tsconfig.json
└── package.json
```

### Provider Stack (layout.tsx)
```
<WalletProvider>              # @mysten/dapp-kit-react
  <QueryClientProvider>       # @tanstack/react-query
    <FloatSyncProvider>       # @floatsync/react
      {children}
    </FloatSyncProvider>
  </QueryClientProvider>
</WalletProvider>
```

### Dependencies
```json
{
  "@floatsync/sdk": "workspace:*",
  "@floatsync/react": "workspace:*",
  "@mysten/dapp-kit-react": "^2.0.0",
  "@mysten/sui": "^2.8.0",
  "@tanstack/react-query": "^5",
  "next": "^15",
  "react": "^19",
  "tailwindcss": "^4"
}
```

### Monorepo Integration
- Package path: `apps/demo` (new `apps/` directory at repo root)
- Add to `pnpm-workspace.yaml`: `apps/*`
- Add to `turbo.json` pipeline if applicable
- Depends on `@floatsync/sdk` and `@floatsync/react` via workspace protocol

## 6. Testnet Configuration

```typescript
// lib/config.ts
export const DEMO_CONFIG = {
  network: 'testnet' as const,
  packageId: '0xe0eb53cce531ab129e499b06ed1a858bb64da08e6c53c18ab4c85ef01306b32a',
  merchantId: '0x4db0ff62d5402f3970028995312a4fd0c243cef9ce6d1e4ace77667155c17c24',
  registryId: '0x2b0584da2655e87873a72977a36741d64e59d68e550016ebb38be5fe243a321f',
  routerConfigId: '0x0bae66f0910b0d22b30d6be5bc2c3f0272ef9c917b34b041608c0fbd31264e8e',
}

// MerchantCap holder (for dashboard): 0x93e30ffb648ddbee6a93518f82eb332a39c1b3457dc7c02544fb105e02d520e2
```

The demo uses the already-deployed v2 contract on SUI testnet. All object IDs from `move/floatsync/deployed.testnet.json`. No additional deployment needed.

## 7. Testing Strategy

### Manual QA (primary for demo app)
- Checkout flow: connect wallet → pay → verify tx on SuiScan
- Subscribe flow: subscribe → verify subscription object on-chain
- Dashboard: verify merchant data matches on-chain state
- Developers: verify all code snippets are copy-able and syntactically correct

### Automated (lightweight)
- Component render tests (no wallet mocking — just UI rendering)
- Build succeeds (`next build`)
- Type check passes (`tsc --noEmit`)

Demo app is a presentation layer over already-tested SDK/React packages (153 + 70 tests). Deep unit testing of the demo itself is low ROI.

## 8. Deployment

**Target:** Vercel (free tier sufficient for demo)
- Auto-deploy from `main` branch
- Environment: `NEXT_PUBLIC_SUI_NETWORK=testnet`
- Domain: TBD (e.g., `demo.floatsync.io` or Vercel subdomain)

## 9. Future Upgrades

Documented in `tasks/notes.md` under "Demo App 未來升級方向". Key items:
- zkLogin / Passkey (remove wallet install barrier)
- Hosted Checkout mode (Stripe Payment Links equivalent)
- Testnet faucet integration (lower onboarding friction)
- Mobile responsive, i18n, dark mode, analytics
