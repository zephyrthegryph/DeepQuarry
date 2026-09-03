import path from 'node:path';

import rspack, { type Configuration } from '@rspack/core';

import oldConfig, {
  createStats,
  TguiChunkManifestPlugin,
  TguiWindowManifestPlugin,
} from './rspack.config';
import { buildWindowGeometryManifest } from './windowGeometryManifest';

const windowGeometryManifest = buildWindowGeometryManifest(
  path.resolve(import.meta.dirname, 'packages', 'tgui', 'interfaces'),
);

export const config = {
  ...oldConfig,
  devtool: 'cheap-module-source-map',
  devServer: {
    hot: true,
  },
  mode: 'development',
  output: {
    ...oldConfig.output,
    path: path.resolve(import.meta.dirname, './public/.tmp'),
  },
  plugins: [
    new rspack.CssExtractRspackPlugin({
      chunkFilename: '[name].bundle.css',
      filename: '[name].bundle.css',
    }),
    new rspack.EnvironmentPlugin({
      NODE_ENV: 'development',
    }),
    new rspack.DefinePlugin({
      __TGUI_WINDOW_GEOMETRY_MANIFEST__: JSON.stringify(windowGeometryManifest),
    }),
    new rspack.HotModuleReplacementPlugin(),
    new TguiChunkManifestPlugin(
      path.resolve(
        import.meta.dirname,
        'public',
        '.tmp',
        'tgui-chunk-manifest.json',
      ),
    ),
    new TguiWindowManifestPlugin(
      path.resolve(
        import.meta.dirname,
        'public',
        '.tmp',
        'tgui-window-manifest.json',
      ),
    ),
  ],
  stats: createStats(false),
} satisfies Configuration;
