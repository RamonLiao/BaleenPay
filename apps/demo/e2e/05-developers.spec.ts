import { test, scrollTo } from './demo.fixture'

test('05 — Developers: SDK Integration', async ({ page }) => {
  await page.goto('/developers')
  await page.waitForSelector('h1:has-text("Integrate FloatSync")')
  await page.waitForTimeout(1000)

  // Scroll through each code snippet
  const snippets = page.locator('.space-y-8 > div')
  const count = await snippets.count()

  for (let i = 0; i < count; i++) {
    await snippets.nth(i).scrollIntoViewIfNeeded()
    await page.waitForTimeout(1200)
  }

  await page.waitForTimeout(1000)
})
