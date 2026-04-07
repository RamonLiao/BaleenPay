# Investor Demo E2E Scripts

## Overview

Playwright E2E test scripts for a 5-minute investor demo. Runs in headed mode with slow motion. Real testnet wallet, real on-chain transactions. User manually operates wallet extension at `page.pause()` breakpoints while screen recording.

## File Structure

```
apps/demo/e2e/
├── playwright.config.ts          # headed, slowMo, video, 5min timeout
├── fixtures/
│   └── demo.fixture.ts           # walletPause helper, screenshot helper
├── 01-landing.spec.ts            # ~30s
├── 02-checkout.spec.ts           # ~60s
├── 03-subscribe.spec.ts          # ~60s
├── 04-dashboard.spec.ts          # ~90s
└── 05-developers.spec.ts         # ~30s
```

## Playwright Config

- `headless: false`
- `slowMo: 300`
- `viewport: 1440×900`
- `video: 'on'` (auto-backup recording)
- `screenshot: 'on'`
- `baseURL: http://localhost:3100`
- `timeout: 300_000` (5 min, accommodates manual wallet pauses)

## Shared Fixture

`walletPause(page, actionDescription)` — logs a console prompt describing the needed wallet action, then calls `page.pause()`. Playwright Inspector shows "Resume" button.

## Flow Details

### 01-landing (~30s)

1. Navigate to `/`
2. Wait for hero section render
3. Scroll to stats section (settlement time, tx cost)
4. Scroll to features grid (6 cards)
5. Scroll to code preview section
6. Screenshot hero + features

### 02-checkout (~60s)

1. Navigate to `/checkout`
2. Click Pro plan ($49)
3. `walletPause` → user connects wallet
4. Wait for WalletGuard to clear, checkout card visible
5. Toggle coin to USDC
6. Click "Pay" button
7. `walletPause` → user signs transaction
8. Wait for success status
9. Screenshot tx digest

### 03-subscribe (~60s)

1. Navigate to `/subscribe`
2. Click Annual plan ($39/mo × 12)
3. Wallet already connected from previous flow
4. Click "Subscribe" button
5. `walletPause` → user signs transaction
6. Wait for success status
7. Screenshot

### 04-dashboard (~90s)

1. Navigate to `/dashboard`
2. Wait for merchant data load
3. Scroll through stats cards (Total Received, Idle Principal, Accrued Yield, Active Subs)
4. Scroll to yield section (accrued yield, vault balance, estimated APY)
5. Click "Claim Yield"
6. `walletPause` → user signs transaction
7. Scroll to pause toggle, click "Pause"
8. `walletPause` → user signs transaction
9. Click "Unpause" to restore state
10. `walletPause` → user signs transaction
11. Scroll to payment history table

### 05-developers (~30s)

1. Navigate to `/developers`
2. Scroll through each code snippet section
3. Screenshot final state

## Prerequisites

- Sui Wallet browser extension installed and configured for testnet
- Test account with sufficient testnet SUI + USDC
- Test account holds MerchantCap for the demo merchant
- Demo app running at `localhost:3100` (`pnpm --filter @baleenpay/demo dev`)

## Non-Goals

- No mocking — all real chain interactions
- No assertions — this is a demo, not CI
- No retry logic — manual operation, restart if stuck
- No wallet automation (Synpress) — manual wallet interaction at pause points
