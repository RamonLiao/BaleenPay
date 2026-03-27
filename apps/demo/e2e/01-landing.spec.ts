import { test, scrollTo } from './demo.fixture'

test('01 — Landing Page Tour', async ({ page }) => {
  await page.goto('/')

  // Hero
  await page.waitForSelector('h1:has-text("Payments infrastructure")')
  await page.waitForTimeout(1500)

  // Stats
  await scrollTo(page, 'text=Settlement Time')
  await page.waitForTimeout(1000)

  // Features
  await scrollTo(page, 'h2:has-text("Everything you need")')
  await page.waitForTimeout(1500)

  // Code preview
  await scrollTo(page, 'h2:has-text("Integrate in minutes")')
  await page.waitForTimeout(1500)

  // CTA
  await scrollTo(page, 'h2:has-text("Ready to try it?")')
  await page.waitForTimeout(1000)
})
