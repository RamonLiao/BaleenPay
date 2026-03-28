import { test } from './demo.fixture'

test('02 — Checkout: One-Time Payment', async ({ page }) => {
  await page.goto('/checkout')
  await page.waitForSelector('h1:has-text("Choose a plan and pay")')
  await page.waitForTimeout(500)

  // Select Pro plan ($49)
  await page.locator('button', { hasText: 'Pro' }).click()
  await page.waitForTimeout(500)

  // Checkout card visible (no wallet guard in demo mode)
  await page.waitForSelector('h2:has-text("Order Summary")')
  await page.waitForTimeout(500)

  // Ensure USDC is selected
  await page.locator('button:has-text("USDC")').click()
  await page.waitForTimeout(300)

  // Click Pay
  await page.locator('button:has-text("Pay $49")').click()

  // Wait for simulated tx: building → signing → confirming → success
  await page.waitForSelector('text=success', { timeout: 10_000 })
  await page.waitForTimeout(2000)
})
