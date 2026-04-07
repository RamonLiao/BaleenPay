import { test, walletPause } from './demo.fixture'

test('02 — Checkout: One-Time Payment', async ({ page }) => {
  await page.goto('/checkout')
  await page.waitForSelector('h1:has-text("Choose a plan and pay")')
  await page.waitForTimeout(500)

  // Select Pro plan ($49)
  await page.locator('button', { hasText: 'Pro' }).click()
  await page.waitForTimeout(500)

  // WalletGuard: connect wallet
  await walletPause(page, 'Connect wallet (Sui Wallet)')

  // After wallet connected, checkout card should be visible
  await page.waitForSelector('h2:has-text("Order Summary")', { timeout: 10_000 })
  await page.waitForTimeout(500)

  // Ensure USDC is selected
  await page.locator('button:has-text("USDC")').click()
  await page.waitForTimeout(300)

  // Click Pay — triggers real tx
  await page.locator('button:has-text("Pay $49")').click()

  // Wallet will prompt for signing
  await walletPause(page, 'Approve transaction in wallet')

  // Wait for on-chain confirmation
  await page.waitForSelector('text=success', { timeout: 30_000 })
  await page.waitForTimeout(2000)
})
