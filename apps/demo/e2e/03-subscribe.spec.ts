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
