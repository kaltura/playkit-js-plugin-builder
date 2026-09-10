import {expect, test} from '@playwright/test';

/**
 * E2E for the plugin-template scaffold, against a real `@playkit-js/kaltura-player-js` build and
 * this plugin's own local `dist/` bundle -- no mocked player. Mock provider (`partnerId: -1`),
 * local `media/video.mp4` (reference/testing-strategy.md, "Default to the mock provider"), so
 * there is zero Kaltura network dependency.
 */

test.beforeEach(async ({page}) => {
  await page.goto('/e2e/index.html');
  await page.waitForFunction(() => (window as unknown as {__setupError: string | null}).__setupError === null);
});

test('loads with zero Trusted Types violations under an enforcing CSP', async ({page}) => {
  // Give any first-paint/first-script violation a moment to surface before asserting
  // (reference/security-checklist.md §3: fail the test on any securitypolicyviolation event).
  await page.waitForTimeout(500);
  const violations = await page.evaluate(() => (window as unknown as {__cspViolations: unknown[]}).__cspViolations);
  expect(violations, `securitypolicyviolation events: ${JSON.stringify(violations)}`).toHaveLength(0);
});

test('registers under KalturaPlayer.plugins.pluginTemplate and activates with no setup error', async ({page}) => {
  // registerPlugin() (src/index.ts) registers a factory; KalturaPlayer.plugins.pluginTemplate is
  // whatever object that factory's own module records it as, not necessarily the class itself --
  // assert it exists rather than assuming a specific typeof.
  const registered = await page.evaluate(() => typeof (window as unknown as {KalturaPlayer: {plugins: {pluginTemplate: unknown}}}).KalturaPlayer.plugins.pluginTemplate);
  expect(registered).not.toBe('undefined');
  const setupError = await page.evaluate(() => (window as unknown as {__setupError: string | null}).__setupError);
  expect(setupError).toBeNull();
});
