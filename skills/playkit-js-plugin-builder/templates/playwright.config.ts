import {defineConfig, devices} from '@playwright/test';

const PORT = 4321;

// Community mode uses Playwright (reference/testing-strategy.md, "E2E: Playwright (community) /
// Cypress (internal)"). Chrome is the required browser; firefox is added since this runner
// supports it out of the box with no extra config.
export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: 'list',
  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: 'on-first-retry'
  },
  projects: [
    {name: 'chromium', use: {...devices['Desktop Chrome']}},
    {name: 'firefox', use: {...devices['Desktop Firefox']}}
  ],
  webServer: {
    command: 'node e2e/server.js',
    url: `http://localhost:${PORT}/e2e/index.html`,
    reuseExistingServer: !process.env.CI,
    env: {E2E_PORT: String(PORT)}
  }
});
