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
