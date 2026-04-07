// apps/demo/e2e/playwright.config.ts
import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.ts',
  timeout: 300_000,
  use: {
    headless: false,
    viewport: { width: 1440, height: 900 },
    video: 'on',
    screenshot: 'on',
    baseURL: 'http://localhost:3100',
    launchOptions: {
      slowMo: 300,
    },
  },
  workers: 1,
  fullyParallel: false,
})
