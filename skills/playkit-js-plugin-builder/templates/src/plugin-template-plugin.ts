import { BasePlugin } from '@playkit-js/kaltura-player-js';

export const pluginName = 'pluginTemplate';

/**
 * Config for this plugin. It is empty on purpose: this is the minimal scaffold.
 * Add your own fields here, and validate the merged config in the constructor
 * (see reference/config-and-validation.md for the shallow-vs-deep merge footgun
 * and the normalizeConfig pattern) rather than trusting the host page's config.
 */
// eslint-disable-next-line @typescript-eslint/no-empty-object-type -- intentionally empty; add your config fields here.
export interface PluginTemplateConfig {}

/**
 * An empty PlayKit-JS player plugin. Extends BasePlugin and implements just enough
 * of the lifecycle to be a valid, well-behaved plugin: a config type, `isValid()`,
 * and a `destroy()` that calls `super.destroy()`.
 *
 * Source for the lifecycle contract this follows:
 * reference/base-plugin-api.md (BasePlugin constructor/isValid()/destroy() contract,
 * traced to docs/plans/2026-09-09-plugin-skill-research.md §1-§3).
 */
export class PluginTemplatePlugin extends BasePlugin {
  public static defaultConfig: PluginTemplateConfig = {};

  /**
   * Whether the plugin can activate. Takes no arguments: it is static and cannot
   * read `this.config` (see reference/config-and-validation.md §2). Must return
   * `false` on a class-level reason the plugin can never activate, never throw --
   * a throw here is not caught by the plugin manager and surfaces as a player error.
   * Config-dependent checks belong in the constructor, not here.
   * @returns True when the plugin class itself is activatable.
   */
  public static isValid(): boolean {
    return true;
  }

  /**
   * Called on the player's CHANGE_SOURCE_STARTED event, not on "media loaded".
   * Add your plugin's per-media setup here (for example, `player.ui.addComponent(...)`).
   * @returns Nothing.
   */
  public loadMedia(): void {
    this.logger.debug(`${pluginName} loadMedia`);
  }

  /**
   * Called before `setMedia()`/`loadMedia()` on a player instance that is being
   * reused for a new entry. Reset any per-media state here.
   * @returns Nothing.
   */
  public reset(): void {
    this.logger.debug(`${pluginName} reset`);
  }

  /**
   * Called when the player is destroyed. Must call `super.destroy()` so the
   * plugin's EventManager tears down every listener registered through
   * `this.eventManager.listen(...)`. Never call this from `reset()`: `destroy()`
   * permanently nulls the EventManager's binding map.
   * @returns Nothing.
   */
  public destroy(): void {
    super.destroy();
    this.logger.debug(`${pluginName} destroy`);
  }
}
