import { test } from './demo.fixture'

test('03 — Subscribe: Recurring Payments', async ({ page }) => {
  await page.goto('/subscribe')
  await page.waitForSelector('h1:has-text("Choose a subscription plan")')
  await page.waitForTimeout(500)

  // Select Annual plan ($39/mo × 12 = $468)
  await page.locator('button', { hasText: 'Annual' }).click()
  await page.waitForTimeout(500)

  // Subscription card visible (no wallet guard in demo mode)
  await page.waitForSelector('h2:has-text("Subscription Summary")')
  await page.waitForTimeout(500)

  // Ensure USDC selected
  await page.locator('button:has-text("USDC")').click()
  await page.waitForTimeout(300)

  // Click Subscribe
  await page.locator('button:has-text("Subscribe")').click()

  // Wait for simulated success
  await page.waitForSelector('text=Subscription Active', { timeout: 10_000 })
  await page.waitForTimeout(2000)
})
