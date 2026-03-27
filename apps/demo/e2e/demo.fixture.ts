// apps/demo/e2e/demo.fixture.ts
import { test as base, type Page } from '@playwright/test'

export const test = base.extend<{ demoPage: Page }>({
  demoPage: async ({ page }, use) => {
    await use(page)
  },
})

/**
 * Pause for manual wallet interaction.
 * Logs what action is needed, then opens Playwright Inspector.
 * Click "Resume" in the Inspector to continue.
 */
export async function walletPause(page: Page, action: string) {
  console.log(
    `\n` +
    `┌─────────────────────────────────────────┐\n` +
    `│  🔵 WALLET ACTION NEEDED                │\n` +
    `│  ${action.padEnd(39)}│\n` +
    `│  Press "Resume" in Inspector to continue│\n` +
    `└─────────────────────────────────────────┘\n`
  )
  await page.pause()
}

/** Smooth-scroll to an element for visual effect during recording. */
export async function scrollTo(page: Page, selector: string) {
  await page.locator(selector).first().scrollIntoViewIfNeeded()
  await page.waitForTimeout(800)
}

export { expect } from '@playwright/test'
