import { writeFileSync } from 'node:fs';
import path from 'node:path';

import { defineConfig } from '@rspack/cli';
import rspack, { type StatsOptions } from '@rspack/core';

/**
 * Emits public/tgui-chunk-manifest.json mapping each routable interface NAME to the
 * async chunk file(s) that must be delivered to render it. The DM side (SStgui) reads
 * this so that opening interface X ships exactly X's self-contained chunk (and its CSS)
 * over browse_rsc before the React side lazy-imports it — no mass precache, no
 * dependency-closure tracking (the lazy context is narrowed to entry modules, so each
 * interface chunk bundles its own submodules).
 *
 * Interface name is derived the same way routes.tsx resolves it: strip `interfaces/`,
 * an optional `chompstation/` prefix, and a trailing `/index` — chompstation entries
 * win over root entries of the same name (routes.tsx searches chompstation first).
 */
class TguiChunkManifestPlugin {
  private outFile: string;
  constructor(outFile: string) {
    this.outFile = outFile;
  }
  apply(compiler: any) {
    compiler.hooks.done.tap('TguiChunkManifestPlugin', (stats: any) => {
      const json = stats.toJson({
        chunks: true,
        chunkModules: true,
        nestedModules: true,
        modules: false,
        assets: false,
        reasons: false,
        source: false,
      });
      // Match an interface ENTRY module path: `interfaces/Name.tsx`,
      // `interfaces/Name/index.tsx`, or the `chompstation/` variants. The entry name
      // segment is followed by either `/index.ext` or `.ext` immediately, so deeper
      // submodules (`interfaces/Name/sub/foo.tsx`) never match. `\b` after the ext
      // tolerates the "… + N modules" suffix that production module concatenation adds.
      const entryRe =
        /(?:^|[/\\])interfaces[/\\](chompstation[/\\])?([^/\\]+?)(?:[/\\]index)?\.(?:tsx?|jsx?)\b/;
      // Collect every module name in a chunk, expanding concatenated modules — the
      // concatenation "root" reported at the top level is not always the entry.
      const collectNames = (mods: any[], out: string[]) => {
        for (const m of mods || []) {
          out.push((m.name || m.identifier || '').replace(/\\/g, '/'));
          if (m.modules) collectNames(m.modules, out);
        }
      };
      const manifest: Record<string, string[]> = {};
      const fromChompstation: Record<string, boolean> = {};
      for (const chunk of json.chunks || []) {
        const files: string[] = [
          ...(chunk.files || []),
          ...(chunk.auxiliaryFiles || []),
        ].filter((f: string) => /\.chunk\.(js|css)$/.test(f));
        if (!files.length) continue;
        const names: string[] = [];
        collectNames(chunk.modules, names);
        for (const name of names) {
          const match = name.match(entryRe);
          if (!match) continue;
          const iface = match[2];
          const isChomp = Boolean(match[1]);
          // chompstation entry wins over a same-named root entry.
          if (manifest[iface] && fromChompstation[iface] && !isChomp) continue;
          manifest[iface] = files;
          fromChompstation[iface] = isChomp;
        }
      }
      writeFileSync(this.outFile, JSON.stringify(manifest, null, 0));
    });
  }
}

export function createStats(verbose: boolean): StatsOptions {
  return {
    assets: verbose,
    builtAt: verbose,
    cached: false,
    children: false,
    chunks: false,
    colors: true,
    entrypoints: true,
    hash: false,
    modules: false,
    performance: false,
    timings: verbose,
    version: verbose,
  };
}
const dirname = path.resolve();

export default defineConfig({
  context: dirname,
  devtool: false,
  entry: {
    tgui: './packages/tgui',
    'tgui-panel': './packages/tgui-panel',
    'tgui-say': './packages/tgui-say',
  },
  mode: 'production',
  module: {
    rules: [
      {
        test: /\.([tj]s(x)?|cjs)$/,
        type: 'javascript/auto',
        use: [
          {
            loader: 'builtin:swc-loader',
            options: {
              jsc: {
                parser: {
                  syntax: 'typescript',
                  tsx: true,
                },
                transform: {
                  react: {
                    runtime: 'automatic',
                  },
                },
              },
            },
          },
        ],
      },
      {
        test: /\.(s)?css$/,
        type: 'javascript/auto',
        use: [
          rspack.CssExtractRspackPlugin.loader,
          'css-loader',
          {
            loader: 'sass-loader',
            options: {
              api: 'modern-compiler',
              implementation: 'sass-embedded',
            },
          },
        ],
      },
      {
        test: /\.(png|jpg)$/,
        oneOf: [
          {
            issuer: /\.(s)?css$/,
            type: 'asset/inline',
          },
          {
            type: 'asset/resource',
          },
        ],
        generator: {
          filename: '[name][ext]',
        },
      },

      {
        test: /\.svg$/,
        oneOf: [
          {
            issuer: /\.(s)?css$/,
            type: 'asset/inline',
          },
          {
            type: 'asset/resource',
          },
        ],
        generator: {
          filename: '[name][ext]',
        },
      },
    ],
  },
  optimization: {
    emitOnErrors: false,
    // Disable async chunk splitting so every interface chunk is fully SELF-CONTAINED.
    // rspack's production default (`splitChunks: { chunks: 'async' }`) would hoist code
    // shared between interfaces into separate vendor/common chunks — which the DM
    // send-on-open delivery would then have to track and ship alongside each interface
    // (a dependency closure) or risk a 404 when the shared chunk isn't on the client.
    // One-chunk-per-interface trades a little duplicated bytes (only ever paid per
    // interface a player actually opens, deduped per client) for a delivery model that
    // cannot half-load. Shared library code (React/tgui-core) still lives once in the
    // always-loaded entry bundle, not duplicated here.
    splitChunks: false,
  },
  output: {
    path: path.resolve(dirname, 'public'),
    filename: '[name].bundle.js',
    // Async route chunks get a distinct `.chunk.js` suffix (not `.bundle.js`) so the
    // DM asset layer can enumerate them with a single flist("*.chunk.*") glob, and so
    // the dev reloader (which globs *.{bundle,chunk,hot-update}.*) picks them up.
    chunkFilename: '[name].chunk.js',
    chunkLoadTimeout: 15000,
    // MUST be '' (relative), not '/'. The tgui page is loaded via BYOND browse() whose
    // base URL is the per-process BYOND cache dir; async chunks are delivered there by
    // browse_rsc under their bare filenames. A '/' publicPath would make the runtime
    // request /name.chunk.js (cache-drive root) and 404. '' yields a relative
    // <script src="name.chunk.js"> that resolves against the cache dir — exactly how
    // Byond.loadJs already loads the main bundle.
    publicPath: '',
    assetModuleFilename: '[name][ext]',
  },
  performance: {
    hints: false,
  },
  plugins: [
    new rspack.CssExtractRspackPlugin({
      // Per-async-chunk CSS gets the same `.chunk.css` treatment as JS chunks so the
      // DM glob enumerates it; entry CSS stays `[name].bundle.css`.
      chunkFilename: '[name].chunk.css',
      filename: '[name].bundle.css',
    }),
    new rspack.EnvironmentPlugin({
      NODE_ENV: 'production',
    }),
    new rspack.CircularDependencyRspackPlugin({
      failOnError: true,
      exclude: /node_modules/,
    }),
    new rspack.IgnorePlugin({
      resourceRegExp: /\.test\.tsx?$/,
      contextRegExp: /__mocks__/,
    }),
    new TguiChunkManifestPlugin(
      path.resolve(dirname, 'public', 'tgui-chunk-manifest.json'),
    ),
  ],
  resolve: {
    extensions: ['.tsx', '.ts', '.js', '.jsx'],
    alias: {
      tgui: path.resolve(dirname, './packages/tgui'),
      'tgui-panel': path.resolve(dirname, './packages/tgui-panel'),
      'tgui-say': path.resolve(dirname, './packages/tgui-say'),
      'tgui-dev-server': path.resolve(dirname, './packages/tgui-dev-server'),
    },
  },
  stats: createStats(true),
  target: ['web', 'browserslist:edge >= 123'],
});
