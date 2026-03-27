import { test, walletPause } from './demo.fixture'

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
