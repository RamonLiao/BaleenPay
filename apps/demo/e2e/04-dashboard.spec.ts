import { test, walletPause, scrollTo } from './demo.fixture'

test('04 — Dashboard: Merchant Admin', async ({ page }) => {
  await page.goto('/dashboard')
  await page.waitForSelector('h1:has-text("Dashboard")')

  // WalletGuard: connect wallet (must own MerchantCap)
  await walletPause(page, 'Connect wallet that owns MerchantCap')

  // Merchant data loads from chain — longer timeout
  await page.waitForSelector('text=Total Received', { timeout: 15_000 })
  await page.waitForTimeout(1000)

  // Scroll through stats
  await scrollTo(page, 'text=Active Subscriptions')
  await page.waitForTimeout(1000)

  // Yield section
  await scrollTo(page, 'h3:has-text("Yield Overview")')
  await page.waitForTimeout(1500)

  // Claim Yield (only if accrued > 0)
  const claimBtn = page.locator('button:has-text("Claim Yield")')
  if (await claimBtn.isEnabled()) {
    await claimBtn.click()
    // Wallet will prompt for signing
    await walletPause(page, 'Approve claim yield transaction')
    await page.waitForSelector('text=success', { timeout: 30_000 })
    await page.waitForTimeout(1500)
  }

  // Pause toggle
  await scrollTo(page, 'h3:has-text("Merchant Status")')
  await page.waitForTimeout(500)

  // Payment history
  await scrollTo(page, 'h3:has-text("Payment History")')
  await page.waitForTimeout(2000)
})
