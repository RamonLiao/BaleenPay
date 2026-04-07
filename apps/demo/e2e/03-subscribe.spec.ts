import { test, walletPause } from './demo.fixture'

test('03 — Subscribe: Recurring Payments', async ({ page }) => {
  await page.goto('/subscribe')
  await page.waitForSelector('h1:has-text("Choose a subscription plan")')
  await page.waitForTimeout(500)

  // Select Annual plan
  await page.locator('button', { hasText: 'Annual' }).click()
  await page.waitForTimeout(500)

  // WalletGuard: connect wallet
  await walletPause(page, 'Connect wallet (Sui Wallet)')

  // After wallet connected, subscription card should be visible
  await page.waitForSelector('h2:has-text("Subscription Summary")', { timeout: 10_000 })
  await page.waitForTimeout(500)

  // Ensure USDC selected
  await page.locator('button:has-text("USDC")').click()
  await page.waitForTimeout(300)

  // Click Subscribe — triggers real tx
  await page.locator('button:has-text("Subscribe")').click()

  // Wallet will prompt for signing
  await walletPause(page, 'Approve transaction in wallet')

  // Wait for on-chain confirmation
  await page.waitForSelector('text=Subscription Active', { timeout: 30_000 })
  await page.waitForTimeout(2000)
})
