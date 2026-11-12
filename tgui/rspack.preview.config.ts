import path from 'node:path';

import { defineConfig } from '@rspack/cli';
import rspack from '@rspack/core';

import base from './rspack.config';

/** The bundle behind tools/tgui_preview: every window, sync, rendered from fixtures in a plain browser page. */
const config: any = base as any;
export default defineConfig({
  ...config,
  entry: { preview: './packages/tgui/preview' },
  output: {
    path: path.resolve(process.env.PREVIEW_OUT ?? path.join(import.meta.dirname, '..', 'data', 'tgui_preview')),
    filename: '[name].bundle.js',
    publicPath: '',
    assetModuleFilename: '[name][ext]',
    clean: true,
  },
  optimization: { splitChunks: false, emitOnErrors: true },
  plugins: [
    new rspack.CssExtractRspackPlugin({ filename: '[name].bundle.css' }),
    new rspack.EnvironmentPlugin({ NODE_ENV: 'production' }),
    new rspack.DefinePlugin({ __TGUI_WINDOW_GEOMETRY_MANIFEST__: '{}' }),
    new rspack.HtmlRspackPlugin({
      templateContent:
        '<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0"><div id="app"></div></body></html>',
      filename: 'index.html',
      inject: 'head',
      scriptLoading: 'defer',
    }),
  ],
});
