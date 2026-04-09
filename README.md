# BaleenPay

> Like the baleen of a whale filtering plankton, BaleenPay intercepts and activates the **Payment Float** of SaaS platforms — idle cash flows automatically generate yield through the underlying protocol.

## What It Does

SaaS platforms collect subscription/checkout payments in USDC on Sui. BaleenPay mints branded stablecoins (BrandUSD) via StableLayer, routes the USDC into yield aggregators, and lets merchants claim accumulated yield from a dashboard. The platform's incoming cash flow earns interest while sitting idle.

### User Flow

1. User connects a Sui wallet and pays (e.g., 10 BrandUSD monthly subscription).
2. Payment settles in USDC → minted into BrandUSD via StableLayer.
3. USDC is auto-routed to the StableLayer Yield Aggregator.
4. Merchant monitors principal & accumulated yield on the dashboard, claims yield (full or partial) at any time.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌───────────────────┐
│  Checkout    │────▸│   Router     │────▸│  StableLayer      │
│  Widget      │     │  (routing +  │     │  Yield Aggregator │
│  (pay/sub)   │     │   ledger)    │     └───────────────────┘
└─────────────┘     └──────────────┘
                          │
                    ┌─────┴──────┐
                    │  Merchant  │
                    │  Account   │
                    │  (vault +  │
                    │   yield)   │
                    └────────────┘
```

### Move Contracts (`move/baleenpay/`)

| Module | Purpose |
|--------|---------|
| `payment` | Checkout & subscription accounting (one-off + recurring) |
| `merchant` | Merchant account, vaults, yield tracking (typed per coin) |
| `router` | Routes USDC to StableLayer, manages keeper deposits & yield claims |
| `brand_usd` | Branded stablecoin (OTW-based `Coin<BRAND_USD>`) |
| `events` | On-chain event definitions |

### Packages

| Package | Description |
|---------|-------------|
| `@baleenpay/sdk` | TypeScript SDK — transaction builders, event queries, coin helpers |
| `@baleenpay/react` | React hooks & components — `usePayment`, `useSubscription`, `useClaimYield`, `CheckoutButton`, etc. |
| `@baleenpay/demo` | Next.js 15 demo app — checkout, subscribe, merchant dashboard |

## Tech Stack

- **Blockchain**: Sui (Move 2024 Edition)
- **SDK**: `@mysten/sui` v2, `@mysten/dapp-kit-react` v2
- **Frontend**: Next.js 15, React 19, Tailwind 4, Recharts
- **Monorepo**: pnpm workspaces + Turborepo
- **Testing**: Move tests (203), SDK vitest (187), Playwright e2e

## Getting Started

### Prerequisites

- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install) (match testnet protocol version)
- Node.js >= 18, pnpm >= 9

### Install & Build

```bash
pnpm install
pnpm build          # builds SDK → React → Demo via Turbo
```

### Move Contracts

```bash
cd move/baleenpay
sui move build
sui move test       # 203 tests
```

### Run Demo App

```bash
pnpm --filter @baleenpay/demo dev    # http://localhost:3100
```

### Run Tests

```bash
# SDK tests
pnpm --filter @baleenpay/sdk test

# React package tests
pnpm --filter @baleenpay/react test

# E2E (requires running demo app)
pnpm --filter @baleenpay/demo test:e2e
```

## Testnet Deployment

Package v3: `0x9b13868fe76b775524ae10ca2e1fb19b7cc306b9d0a7879f21487752cb845ec2`

See `deployments/testnet-2026-04-07.json` for full object IDs.

## License

MIT
