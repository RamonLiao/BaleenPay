import { test, scrollTo } from './demo.fixture'

test('04 — Dashboard: Merchant Admin', async ({ page }) => {
  await page.goto('/dashboard')
  await page.waitForSelector('h1:has-text("Dashboard")')

  // Merchant data loads immediately with mock data
  await page.waitForSelector('text=Total Received', { timeout: 5_000 })
  await page.waitForTimeout(1000)

  // Scroll through stats
  await scrollTo(page, 'text=Active Subscriptions')
  await page.waitForTimeout(1000)

  // Yield section
  await scrollTo(page, 'h3:has-text("Yield Overview")')
  await page.waitForTimeout(1500)

  // Claim Yield
  const claimBtn = page.locator('button:has-text("Claim Yield")')
  if (await claimBtn.isEnabled()) {
    await claimBtn.click()
    // Wait for simulated claim success
    await page.waitForSelector('text=success', { timeout: 10_000 })
    await page.waitForTimeout(1500)
  }

  // Pause toggle
  await scrollTo(page, 'h3:has-text("Merchant Status")')
  await page.waitForTimeout(500)

  const pauseBtn = page.locator('button:has-text("Pause")')
  if (await pauseBtn.isVisible()) {
    await pauseBtn.click()
    await page.waitForTimeout(1500)
  }

  // Payment history
  await scrollTo(page, 'h3:has-text("Payment History")')
  await page.waitForTimeout(2000)
})
