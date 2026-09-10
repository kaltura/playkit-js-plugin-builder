const path = require('path');
const webpack = require('webpack');
const packageData = require('./package.json');

module.exports = (env, argv) => ({
  target: 'web',
  entry: path.resolve(__dirname, 'src/index.ts'),
  devtool: argv.mode === 'production' ? false : 'source-map',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'playkit-js-plugin-template.js',
    library: {
      type: 'umd',
      name: ['KalturaPlayer', 'plugins', 'pluginTemplate']
    },
    globalObject: 'this'
  },
  resolve: {
    extensions: ['.ts', '.tsx', '.js']
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: 'ts-loader',
        exclude: /node_modules/
      }
    ]
  },
  // These map to globals that the host page's Kaltura Player UMD bundle attaches to `window`.
  // Never bundle these; every plugin on the page must share one player, one UI runtime, one Preact
  // instance (reference/coding-guidelines.md). This stub imports only from
  // `@playkit-js/kaltura-player-js`, but the UI/preact externals are kept here so a scaffolder who
  // adds `addComponent` UI later inherits correct config instead of a bundled, duplicate Preact.
  //
  // A plain string external (e.g. 'KalturaPlayer') is only correct for a single top-level global.
  // For a nested global (`window.KalturaPlayer.ui`), webpack's UMD `root` target needs the
  // dotted-path array form (`{root: ['KalturaPlayer', 'ui'], ...}`); a dotted *string* like
  // 'KalturaPlayer.ui' is NOT split into a property path -- it makes the `root` branch look up a
  // literal property named "KalturaPlayer.ui" on `window`, which never exists, so
  // `require('@playkit-js/playkit-js-ui')` resolves to `undefined` in a real script-tag load.
  externals: {
    '@playkit-js/kaltura-player-js': 'KalturaPlayer',
    '@playkit-js/playkit-js-ui': {
      root: ['KalturaPlayer', 'ui'],
      commonjs: '@playkit-js/playkit-js-ui',
      commonjs2: '@playkit-js/playkit-js-ui',
      amd: '@playkit-js/playkit-js-ui'
    },
    '@playkit-js/playkit-js': {
      root: ['KalturaPlayer', 'core'],
      commonjs: '@playkit-js/playkit-js',
      commonjs2: '@playkit-js/playkit-js',
      amd: '@playkit-js/playkit-js'
    },
    preact: {
      root: ['KalturaPlayer', 'ui', 'preact'],
      commonjs: 'preact',
      commonjs2: 'preact',
      amd: 'preact'
    },
    'preact-i18n': {
      root: ['KalturaPlayer', 'ui', 'preacti18n'],
      commonjs: 'preact-i18n',
      commonjs2: 'preact-i18n',
      amd: 'preact-i18n'
    },
    'preact/hooks': {
      root: ['KalturaPlayer', 'ui', 'preactHooks'],
      commonjs: 'preact/hooks',
      commonjs2: 'preact/hooks',
      amd: 'preact/hooks'
    }
  },
  plugins: [
    new webpack.DefinePlugin({
      __VERSION__: JSON.stringify(packageData.version),
      __NAME__: JSON.stringify(packageData.name)
    })
  ]
});
