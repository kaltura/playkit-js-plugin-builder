import {describe, expect, it, vi} from 'vitest';
import {registerPlugin} from '@playkit-js/kaltura-player-js';
import {pluginName, PluginTemplatePlugin} from '../../src/plugin-template-plugin';

/**
 * Minimal fake `player` satisfying only the surface `BasePlugin`'s own constructor and
 * `EventManager` need: `addEventListener`/`removeEventListener` for the event target, and
 * `dispatchEvent` for `this.player.dispatchEvent(...)`. No real `KalturaPlayer` instance --
 * see reference/testing-strategy.md, "Mocking the player".
 */
function createMockPlayer(): {addEventListener: ReturnType<typeof vi.fn>; removeEventListener: ReturnType<typeof vi.fn>; dispatchEvent: ReturnType<typeof vi.fn>} {
  return {
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn()
  };
}

function buildPlugin(): PluginTemplatePlugin {
  const player = createMockPlayer();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- the mock only needs to satisfy the slice of the real player BasePlugin's constructor touches.
  return new PluginTemplatePlugin(pluginName, player as any, {});
}

describe('registerPlugin', () => {
  it('returns true for PluginTemplatePlugin, proving the class hierarchy is intact', () => {
    // A unique name per test run avoids colliding with a real "pluginTemplate" registration made by
    // importing src/index.ts elsewhere in the suite (registerPlugin returns false, not an error, on
    // a duplicate name -- reference/testing-strategy.md, "registerPlugin return value").
    const uniqueName = `pluginTemplate-test-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const result = registerPlugin(uniqueName, PluginTemplatePlugin);
    expect(result).toBe(true);
  });
});

describe('PluginTemplatePlugin lifecycle', () => {
  it('isValid() returns true with no arguments', () => {
    expect(PluginTemplatePlugin.isValid()).toBe(true);
  });

  it('constructs, runs loadMedia()/reset(), and destroy() without throwing', () => {
    const plugin = buildPlugin();
    expect(() => plugin.loadMedia()).not.toThrow();
    expect(() => plugin.reset()).not.toThrow();
    expect(() => plugin.destroy()).not.toThrow();
  });
});
