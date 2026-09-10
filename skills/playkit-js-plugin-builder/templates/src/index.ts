import { registerPlugin } from '@playkit-js/kaltura-player-js';
import { pluginName, PluginTemplatePlugin } from './plugin-template-plugin';
import type { PluginTemplateConfig } from './plugin-template-plugin';

// RENAME: this whole scaffold is a placeholder. Before shipping, replace every
// occurrence of "pluginTemplate" / "PluginTemplate" / "plugin-template" with your
// plugin's real name (see webpack.config.js and package.json for the other spots,
// and SCAFFOLDER-NOTES.md / docs/guide.md for the full checklist).

const registered = registerPlugin(pluginName, PluginTemplatePlugin);
if (!registered) {
  // registerPlugin() returns false silently on an invalid class or a duplicate
  // name -- it never throws. Fail loudly here instead of shipping a plugin that
  // silently never activates.
  throw new Error(`Failed to register plugin "${pluginName}": registerPlugin() returned false.`);
}

export { pluginName, PluginTemplatePlugin };
export type { PluginTemplateConfig };
export default PluginTemplatePlugin;
