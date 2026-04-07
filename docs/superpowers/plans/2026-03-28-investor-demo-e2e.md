# Investor Demo E2E Scripts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 5 Playwright E2E test scripts that walk through the demo app for a 5-minute investor recording.

**Architecture:** Each spec file is a standalone Playwright test that navigates one page, clicks UI elements with `slowMo: 300`, and calls `page.pause()` before wallet interactions. A shared fixture provides the `walletPause` helper. No mocking, no assertions beyond `waitForSelector`.

**Tech Stack:** Playwright, TypeScript

---

## File Structure

```
apps/demo/e2e/
├── playwright.config.ts          # headed, slowMo, video, 5min timeout
├── demo.fixture.ts               # walletPause helper, extended test
├── 01-landing.spec.ts            # ~30s
├── 02-checkout.spec.ts           # ~60s
├── 03-subscribe.spec.ts          # ~60s
├── 04-dashboard.spec.ts          # ~90s
└── 05-developers.spec.ts         # ~30s
```

---

### Task 1: Install Playwright & Config

**Files:**
- Modify: `apps/demo/package.json` (add devDependency)
- Create: `apps/demo/e2e/playwright.config.ts`

- [ ] **Step 1: Install Playwright**

```bash
cd apps/demo && pnpm add -D @playwright/test
```

- [ ] **Step 2: Create playwright.config.ts**

```ts
// apps/demo/e2e/playwright.config.ts
import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.ts',
  timeout: 300_000,
  use: {
    headless: false,
    viewport: { width: 1440, height: 900 },
    video: 'on',
    screenshot: 'on',
    baseURL: 'http://localhost:3100',
    launchOptions: {
      slowMo: 300,
    },
  },
  workers: 1,             // sequential — demo order matters
  fullyParallel: false,
})
```

- [ ] **Step 3: Add script to package.json**

Add to `apps/demo/package.json` scripts:

```json
"demo": "npx playwright test --config e2e/playwright.config.ts --headed"
```

- [ ] **Step 4: Verify config loads**

```bash
cd apps/demo && npx playwright test --config e2e/playwright.config.ts --list
```

Expected: "No tests found" (no spec files yet), no config errors.

- [ ] **Step 5: Commit**

```bash
git add apps/demo/package.json apps/demo/e2e/playwright.config.ts
git commit -m "chore(demo): add Playwright config for investor demo E2E"
```

---

### Task 2: Shared Demo Fixture

**Files:**
- Create: `apps/demo/e2e/demo.fixture.ts`

- [ ] **Step 1: Create demo.fixture.ts**

```ts
// apps/demo/e2e/demo.fixture.ts
import { test as base, type Page } from '@playwright/test'

export const test = base.extend<{ demoPage: Page }>({
  demoPage: async ({ page }, use) => {
    await use(page)
  },
})

/**
 * Pause for manual wallet interaction.
 * Logs what action is needed, then opens Playwright Inspector.
 * Click "Resume" in the Inspector to continue.
 */
export async function walletPause(page: Page, action: string) {
  console.log(
    `\n` +
    `┌─────────────────────────────────────────┐\n` +
    `│  🔵 WALLET ACTION NEEDED                │\n` +
    `│  ${action.padEnd(39)}│\n` +
    `│  Press "Resume" in Inspector to continue│\n` +
    `└─────────────────────────────────────────┘\n`
  )
  await page.pause()
}

/** Smooth-scroll to an element for visual effect during recording. */
export async function scrollTo(page: Page, selector: string) {
  await page.locator(selector).first().scrollIntoViewIfNeeded()
  await page.waitForTimeout(800)
}

export { expect } from '@playwright/test'
```

- [ ] **Step 2: Commit**

```bash
git add apps/demo/e2e/demo.fixture.ts
git commit -m "chore(demo): add shared Playwright demo fixture with walletPause helper"
```

---

### Task 3: 01-landing.spec.ts

**Files:**
- Create: `apps/demo/e2e/01-landing.spec.ts`

UI selectors are based on the actual landing page (`apps/demo/app/page.tsx`):
- Hero section: `h1` with "Payments infrastructure"
- Stats section: text "<1s", "$0.001" etc.
- Features section: `h2` with "Everything you need"
- Code preview section: `pre` with code
- CTA section: `h2` with "Ready to try it?"

- [ ] **Step 1: Create spec**

```ts
// apps/demo/e2e/01-landing.spec.ts
import { test, scrollTo } from './demo.fixture'

test('01 — Landing Page Tour', async ({ page }) => {
  await page.goto('/')

  // Hero
  await page.waitForSelector('h1:has-text("Payments infrastructure")')
  await page.waitForTimeout(1500)

  // Stats
  await scrollTo(page, 'text=Settlement Time')
  await page.waitForTimeout(1000)

  // Features
  await scrollTo(page, 'h2:has-text("Everything you need")')
  await page.waitForTimeout(1500)

  // Code preview
  await scrollTo(page, 'h2:has-text("Integrate in minutes")')
  await page.waitForTimeout(1500)

  // CTA
  await scrollTo(page, 'h2:has-text("Ready to try it?")')
  await page.waitForTimeout(1000)
})
```

- [ ] **Step 2: Verify it runs**

Start the dev server in a separate terminal first:
```bash
cd apps/demo && pnpm dev
```

Then run the spec:
```bash
cd apps/demo && npx playwright test --config e2e/playwright.config.ts 01-landing
```

Expected: Browser opens, scrolls through landing page, closes. PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/demo/e2e/01-landing.spec.ts
git commit -m "feat(demo): add landing page E2E demo script"
```

---

### Task 4: 02-checkout.spec.ts

**Files:**
- Create: `apps/demo/e2e/02-checkout.spec.ts`

UI selectors from `apps/demo/app/checkout/page.tsx`:
- Product cards: `<button>` containing product name text (e.g. "Pro")
- WalletGuard: `h2:has-text("Connect Your Wallet")` with a `ConnectButton`
- Coin toggle: buttons with text "USDC" / "SUI" inside CoinToggle
- Pay button: `button:has-text("Pay $49 with USDC")`
- Success: TxStatus renders digest when `status === 'success'`

- [ ] **Step 1: Create spec**

```ts
// apps/demo/e2e/02-checkout.spec.ts
import { test, walletPause, scrollTo } from './demo.fixture'

test('02 — Checkout: One-Time Payment', async ({ page }) => {
  await page.goto('/checkout')
  await page.waitForSelector('h1:has-text("Choose a plan and pay")')
  await page.waitForTimeout(500)

  // Select Pro plan ($49) — it's selected by default, but click to highlight
  await page.locator('button', { hasText: 'Pro' }).click()
  await page.waitForTimeout(500)

  // Connect wallet
  await walletPause(page, 'Connect your Sui Wallet')

  // After wallet connected, WalletGuard disappears, checkout card shows
  await page.waitForSelector('h2:has-text("Order Summary")')
  await page.waitForTimeout(500)

  // Ensure USDC is selected (default)
  await page.locator('button:has-text("USDC")').click()
  await page.waitForTimeout(300)

  // Click Pay
  await page.locator('button:has-text("Pay $49")').click()
  await page.waitForTimeout(300)

  // Sign transaction in wallet
  await walletPause(page, 'Sign the payment transaction')

  // Wait for success
  await page.waitForSelector('text=success', { timeout: 30_000 })
  await page.waitForTimeout(2000)
})
```

- [ ] **Step 2: Run and verify**

```bash
cd apps/demo && npx playwright test --config e2e/playwright.config.ts 02-checkout
```

Expected: Opens checkout, you manually connect wallet + sign tx, ends with success. PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/demo/e2e/02-checkout.spec.ts
git commit -m "feat(demo): add checkout E2E demo script"
```

---

### Task 5: 03-subscribe.spec.ts

**Files:**
- Create: `apps/demo/e2e/03-subscribe.spec.ts`

UI selectors from `apps/demo/app/subscribe/page.tsx`:
- Plan cards: `<button>` containing plan name text (e.g. "Annual")
- Subscribe button: `button:has-text("Subscribe — $468 with USDC")`
- Success box: `.bg-emerald-50` with "Subscription Active"

- [ ] **Step 1: Create spec**

```ts
// apps/demo/e2e/03-subscribe.spec.ts
import { test, walletPause } from './demo.fixture'

test('03 — Subscribe: Recurring Payments', async ({ page }) => {
  await page.goto('/subscribe')
  await page.waitForSelector('h1:has-text("Choose a subscription plan")')
  await page.waitForTimeout(500)

  // Select Annual plan ($39/mo × 12 = $468)
  await page.locator('button', { hasText: 'Annual' }).click()
  await page.waitForTimeout(500)

  // If wallet not connected yet (running standalone), pause for connect
  const walletGuard = page.locator('h2:has-text("Connect Your Wallet")')
  if (await walletGuard.isVisible()) {
    await walletPause(page, 'Connect your Sui Wallet')
  }

  // Wait for subscription card
  await page.waitForSelector('h2:has-text("Subscription Summary")')
  await page.waitForTimeout(500)

  // Ensure USDC selected
  await page.locator('button:has-text("USDC")').click()
  await page.waitForTimeout(300)

  // Click Subscribe
  await page.locator('button:has-text("Subscribe")').click()
  await page.waitForTimeout(300)

  // Sign transaction
  await walletPause(page, 'Sign the subscription transaction')

  // Wait for success
  await page.waitForSelector('text=Subscription Active', { timeout: 30_000 })
  await page.waitForTimeout(2000)
})
```

- [ ] **Step 2: Run and verify**

```bash
cd apps/demo && npx playwright test --config e2e/playwright.config.ts 03-subscribe
```

Expected: Opens subscribe, selects Annual, you sign tx, success shown. PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/demo/e2e/03-subscribe.spec.ts
git commit -m "feat(demo): add subscription E2E demo script"
```

---

### Task 6: 04-dashboard.spec.ts

**Files:**
- Create: `apps/demo/e2e/04-dashboard.spec.ts`

UI selectors from `apps/demo/app/dashboard/page.tsx`:
- Stats: `StatCard` with labels "Total Received", "Idle Principal", "Accrued Yield", "Active Subscriptions"
- Yield section: `h3:has-text("Yield Overview")`
- Claim button: `button:has-text("Claim Yield")`
- Pause button: `button:has-text("Pause")` or `button:has-text("Unpause")`
- Payment history: `h3:has-text("Payment History")`

- [ ] **Step 1: Create spec**

```ts
// apps/demo/e2e/04-dashboard.spec.ts
import { test, walletPause, scrollTo } from './demo.fixture'

test('04 — Dashboard: Merchant Admin', async ({ page }) => {
  await page.goto('/dashboard')
  await page.waitForSelector('h1:has-text("Dashboard")')

  // Connect wallet if needed
  const walletGuard = page.locator('h2:has-text("Connect Your Wallet")')
  if (await walletGuard.isVisible()) {
    await walletPause(page, 'Connect wallet with MerchantCap')
  }

  // Wait for merchant data to load
  await page.waitForSelector('text=Total Received', { timeout: 15_000 })
  await page.waitForTimeout(1000)

  // Scroll through stats
  await scrollTo(page, 'text=Active Subscriptions')
  await page.waitForTimeout(1000)

  // Yield section
  await scrollTo(page, 'h3:has-text("Yield Overview")')
  await page.waitForTimeout(1500)

  // Claim Yield (only if button is enabled)
  const claimBtn = page.locator('button:has-text("Claim Yield")')
  if (await claimBtn.isEnabled()) {
    await claimBtn.click()
    await walletPause(page, 'Sign the claim yield transaction')
    await page.waitForTimeout(2000)
  } else {
    await page.waitForTimeout(1000)
  }

  // Pause toggle
  await scrollTo(page, 'h3:has-text("Merchant Status")')
  await page.waitForTimeout(500)

  const pauseBtn = page.locator('button:has-text("Pause")')
  if (await pauseBtn.isVisible()) {
    await pauseBtn.click()
    await walletPause(page, 'Sign the pause transaction')
    await page.waitForTimeout(1500)

    // Unpause to restore state
    const unpauseBtn = page.locator('button:has-text("Unpause")')
    await unpauseBtn.waitFor({ timeout: 10_000 })
    await unpauseBtn.click()
    await walletPause(page, 'Sign the unpause transaction')
    await page.waitForTimeout(1500)
  }

  // Payment history
  await scrollTo(page, 'h3:has-text("Payment History")')
  await page.waitForTimeout(2000)
})
```

- [ ] **Step 2: Run and verify**

```bash
cd apps/demo && npx playwright test --config e2e/playwright.config.ts 04-dashboard
```

Expected: Dashboard loads, scrolls through stats/yield, you sign claim + pause/unpause, shows payment history. PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/demo/e2e/04-dashboard.spec.ts
git commit -m "feat(demo): add dashboard E2E demo script"
```

---

### Task 7: 05-developers.spec.ts

**Files:**
- Create: `apps/demo/e2e/05-developers.spec.ts`

UI selectors from `apps/demo/app/developers/page.tsx`:
- Header: `h1:has-text("Integrate BaleenPay")`
- Code snippets: `CodeSnippet` components rendered in `.space-y-8` container

- [ ] **Step 1: Create spec**

```ts
// apps/demo/e2e/05-developers.spec.ts
import { test, scrollTo } from './demo.fixture'

test('05 — Developers: SDK Integration', async ({ page }) => {
  await page.goto('/developers')
  await page.waitForSelector('h1:has-text("Integrate BaleenPay")')
  await page.waitForTimeout(1000)

  // Scroll through each code snippet
  const snippets = page.locator('.space-y-8 > div')
  const count = await snippets.count()

  for (let i = 0; i < count; i++) {
    await snippets.nth(i).scrollIntoViewIfNeeded()
    await page.waitForTimeout(1200)
  }

  await page.waitForTimeout(1000)
})
```

- [ ] **Step 2: Run and verify**

```bash
cd apps/demo && npx playwright test --config e2e/playwright.config.ts 05-developers
```

Expected: Scrolls through code snippets page. PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/demo/e2e/05-developers.spec.ts
git commit -m "feat(demo): add developers page E2E demo script"
```

---

### Task 8: Full Run Smoke Test

- [ ] **Step 1: Run all 5 specs in order**

```bash
cd apps/demo && npx playwright test --config e2e/playwright.config.ts --headed
```

Expected: All 5 specs run sequentially (landing → checkout → subscribe → dashboard → developers). Videos saved in `test-results/`.

- [ ] **Step 2: Check video output**

```bash
ls apps/demo/test-results/
```

Each spec should have a `.webm` video file.

- [ ] **Step 3: Final commit**

```bash
git add -A apps/demo/e2e/ apps/demo/test-results/.gitkeep
git commit -m "feat(demo): complete investor demo E2E suite — 5 flows, ~5min total"
```
