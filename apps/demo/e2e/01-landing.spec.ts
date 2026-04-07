import { test, scrollTo } from './demo.fixture'

test('01 — Landing Page Tour', async ({ page }) => {
  await page.goto('/')

  // Hero
  await page.waitForSelector('h1:has-text("payment float")')
  await page.waitForTimeout(1500)

  // Stats
  await scrollTo(page, 'text=Settlement')
  await page.waitForTimeout(1000)

  // Problem section
  await scrollTo(page, 'h2:has-text("SaaS revenue")')
  await page.waitForTimeout(1500)

  // How It Works
  await scrollTo(page, 'h2:has-text("From payment to yield")')
  await page.waitForTimeout(1500)

  // Features
  await scrollTo(page, 'h2:has-text("Payment infrastructure")')
  await page.waitForTimeout(1500)

  // Code preview
  await scrollTo(page, 'h2:has-text("Integrate in minutes")')
  await page.waitForTimeout(1500)

  // CTA
  await scrollTo(page, 'h2:has-text("Stop leaving money")')
  await page.waitForTimeout(1000)
})
