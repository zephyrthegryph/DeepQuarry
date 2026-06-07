#!/usr/bin/env node

/**
 * Build script for /tg/station 13 codebase.
 *
 * This script uses Juke Build, read the docs here:
 * https://github.com/stylemistake/juke-build
 */

import fs from 'node:fs';
import Juke from './juke/index.js';
import { bun, bunRoot } from './lib/bun';
import { DreamDaemon, DreamMaker, NamedVersionFile } from './lib/byond';
import { prependDefines } from './lib/tgs';

export const TGS_MODE = process.env.CBT_BUILD_MODE === 'TGS';

// DQEdit — renamed from 'vorestation'
export const DME_NAME = 'deepquarry';

Juke.chdir('../..', import.meta.url);

export const DefineParameter = new Juke.Parameter({
  type: 'string[]',
  alias: 'D',
});

export const PortParameter = new Juke.Parameter({
  type: 'string',
  alias: 'p',
});

export const DmVersionParameter = new Juke.Parameter({
  type: 'string',
});

export const CiParameter = new Juke.Parameter({ type: 'boolean' });

export const WarningParameter = new Juke.Parameter({
  type: 'string[]',
  alias: 'W',
});

export const NoWarningParameter = new Juke.Parameter({
  type: 'string[]',
  alias: 'I',
});

export const DmMapsIncludeTarget = new Juke.Target({
  executes: async () => {
    const folders = [
      ...Juke.glob('_maps/map_files/**/modular_pieces/*.dmm'),
      ...Juke.glob('_maps/RandomRuins/**/*.dmm'),
      ...Juke.glob('_maps/RandomZLevels/**/*.dmm'),
      ...Juke.glob('_maps/shuttles/**/*.dmm'),
      ...Juke.glob('_maps/templates/**/*.dmm'),
    ];
    const content = `${folders
      .map((file) => file.replace('maps/', ''))
      .map((file) => `#include "${file}"`)
      .join('\n')}\n`;
    fs.writeFileSync('_maps/templates.dm', content);
  },
});

// DQAdd Start — regenerate .dmi files from their PNG + .dmi.toml sources
// before DM compile. Architecture A migration: every DMI has editable
// PNG + TOML sources alongside it; this target re-packs them when stale.
//
// No `inputs`/`outputs` declared on purpose: build_step.py does its own
// per-file mtime check, so letting Juke pre-glob 4800+ source files just
// to decide whether to invoke us is pure overhead — Juke's stat pass
// costs ~5s/build, build_step.py's own dirty-check is 0.9s. The target
// runs unconditionally; the script no-ops when nothing's stale.
export const IconRepackTarget = new Juke.Target({
  executes: async () => {
    await Juke.exec('python3', [
      '-m', 'tools.dq_icons.build_step',
      '--output', 'icons/gen',
      'icons', 'maps',
    ]);
  },
});
// DQAdd End

export const DmTarget = new Juke.Target({
  parameters: [
    DefineParameter,
    DmVersionParameter,
    WarningParameter,
    NoWarningParameter,
  ],
  dependsOn: ({ get }) => [
    get(DefineParameter).includes('ALL_MAPS') && DmMapsIncludeTarget,
    IconRepackTarget, // DQAdd — regenerate .dmi from PNG+TOML before DM compile
  ],
  inputs: [
    '_maps/map_files/generic/**',
    'maps/**/*.dm',
    'code/**',
    'html/**',
    'icons/**',
    'interface/**',
    'sound/**',
    'tgui/public/tgui.html',
    `${DME_NAME}.dme`,
    NamedVersionFile,
  ],
  outputs: ({ get }) => {
    if (get(DmVersionParameter)) {
      return []; // Always rebuild when dm version is provided
    }
    return [`${DME_NAME}.dmb`, `${DME_NAME}.rsc`];
  },
  executes: async ({ get }) => {
    await DreamMaker(`${DME_NAME}.dme`, {
      defines: ['CBT', ...get(DefineParameter)],
      warningsAsErrors: get(WarningParameter).includes('error'),
      ignoreWarningCodes: get(NoWarningParameter),
      namedDmVersion: get(DmVersionParameter),
    });
  },
});

export const DmTestTarget = new Juke.Target({
  parameters: [
    DefineParameter,
    DmVersionParameter,
    WarningParameter,
    NoWarningParameter,
  ],
  dependsOn: ({ get }) => [
    get(DefineParameter).includes('ALL_MAPS') && DmMapsIncludeTarget,
    IconRepackTarget,
  ],
  executes: async ({ get }) => {
    fs.copyFileSync(`${DME_NAME}.dme`, `${DME_NAME}.test.dme`);
    await DreamMaker(`${DME_NAME}.test.dme`, {
      defines: ['CBT', 'CIBUILDING', ...get(DefineParameter)],
      warningsAsErrors: get(WarningParameter).includes('error'),
      ignoreWarningCodes: get(NoWarningParameter),
      namedDmVersion: get(DmVersionParameter),
    });
    Juke.rm('data/logs/ci', { recursive: true });
    const options = {
      dmbFile: `${DME_NAME}.test.dmb`,
      namedDmVersion: get(DmVersionParameter),
    };
    // DreamDaemon on Windows exits non-zero even on a clean test run
    // (the world qdels itself which BYOND reports as abnormal exit).
    // The authoritative success signal is data/logs/ci/clean_run.lk
    // written by world.dm:488, so swallow the exit code and check
    // that file instead.
    try {
      await DreamDaemon(
        options,
        '-close',
        '-trusted',
        '-verbose',
        '-params',
        'log-directory=ci',
      );
    } catch (err) {
      // Swallow — clean_run.lk check below is the real verdict.
    }
    Juke.rm('*.test.*');
    try {
      const cleanRun = fs.readFileSync('data/logs/ci/clean_run.lk', 'utf-8');
      console.log(cleanRun);
    } catch (err) {
      Juke.logger.error('Test run was not clean, exiting');
      throw new Juke.ExitCode(1);
    }
  },
});

export const AutowikiTarget = new Juke.Target({
  parameters: [
    DefineParameter,
    DmVersionParameter,
    WarningParameter,
    NoWarningParameter,
  ],
  dependsOn: ({ get }) => [
    get(DefineParameter).includes('ALL_MAPS') && DmMapsIncludeTarget,
    IconRepackTarget,
  ],
  outputs: ['data/autowiki_edits.txt'],
  executes: async ({ get }) => {
    fs.copyFileSync(`${DME_NAME}.dme`, `${DME_NAME}.test.dme`);
    await DreamMaker(`${DME_NAME}.test.dme`, {
      defines: ['CBT', 'AUTOWIKI', ...get(DefineParameter)],
      warningsAsErrors: get(WarningParameter).includes('error'),
      ignoreWarningCodes: get(NoWarningParameter),
      namedDmVersion: get(DmVersionParameter),
    });
    Juke.rm('data/autowiki_edits.txt');
    Juke.rm('data/autowiki_files', { recursive: true });
    Juke.rm('data/logs/ci', { recursive: true });

    const options = {
      dmbFile: `${DME_NAME}.test.dmb`,
      namedDmVersion: get(DmVersionParameter),
    };
    await DreamDaemon(
      options,
      '-close',
      '-trusted',
      '-verbose',
      '-params',
      'log-directory=ci',
    );
    Juke.rm('*.test.*');
    if (!fs.existsSync('data/autowiki_edits.txt')) {
      Juke.logger.error('Autowiki did not generate an output, exiting');
      throw new Juke.ExitCode(1);
    }
  },
});

export const BunTarget = new Juke.Target({
  parameters: [CiParameter],
  inputs: ['tgui/**/package.json'],
  // DQAdd Start — skip `bun install` when tgui/node_modules is newer
  // than every package.json + bun.lock under tgui/. Without this Juke
  // re-runs `bun install --frozen-lockfile` on every build (~5s) even
  // when nothing has changed; the install itself then no-ops in ~70ms
  // but the spawn overhead is real. Same onlyWhen pattern as
  // BiomeInstallTarget below.
  onlyWhen: () => {
    if (!fs.existsSync('tgui/node_modules')) return true;
    try {
      const nmMt = fs.statSync('tgui/node_modules').mtimeMs;
      if (fs.statSync('tgui/bun.lock').mtimeMs > nmMt) return true;
      // tgui/**/package.json matches inside tgui/node_modules/ too,
      // where Bun's per-install file writes always look "newer" than
      // the parent directory. Filter those out so we only watch
      // authored workspace package.json files.
      for (const pkg of Juke.glob('tgui/**/package.json')) {
        if (pkg.includes('node_modules')) continue;
        if (fs.statSync(pkg).mtimeMs > nmMt) return true;
      }
      return false;
    } catch {
      return true; // bail conservatively if any stat fails
    }
  },
  // DQAdd End
  executes: () => {
    return bun('install', '--frozen-lockfile', '--ignore-scripts');
  },
});

export const BiomeInstallTarget = new Juke.Target({
  dependsOn: [BunTarget],
  inputs: ['package.json', 'bun.lock'],
  onlyWhen: () => {
    return Juke.glob('node_modules/@biomejs/**').length === 0;
  },
  executes: () => {
    return bunRoot('install');
  },
});

export const TgFontTarget = new Juke.Target({
  dependsOn: [BunTarget],
  inputs: [
    'tgui/packages/tgfont/**/*.+(js|mjs|svg)',
    'tgui/packages/tgfont/package.json',
  ],
  outputs: [
    'tgui/packages/tgfont/dist/tgfont.css',
    'tgui/packages/tgfont/dist/tgfont.woff2',
  ],
  executes: async () => {
    await Juke.exec('bun', ['run', 'tgfont:build'], {
      cwd: 'tgui/packages/tgfont',
    });
    fs.mkdirSync('tgui/packages/tgfont/static', { recursive: true });
    fs.copyFileSync(
      'tgui/packages/tgfont/dist/tgfont.css',
      'tgui/packages/tgfont/static/tgfont.css',
    );
    fs.copyFileSync(
      'tgui/packages/tgfont/dist/tgfont.woff2',
      'tgui/packages/tgfont/static/tgfont.woff2',
    );
  },
});

export const TguiTarget = new Juke.Target({
  dependsOn: [BunTarget, BiomeInstallTarget],
  inputs: [
    'tgui/rspack.config.ts',
    'tgui/**/package.json',
    'tgui/packages/**/*.+(js|cjs|ts|tsx|jsx|scss)',
  ],
  outputs: [
    'tgui/public/tgui.bundle.css',
    'tgui/public/tgui.bundle.js',
    'tgui/public/tgui-panel.bundle.css',
    'tgui/public/tgui-panel.bundle.js',
    'tgui/public/tgui-say.bundle.css',
    'tgui/public/tgui-say.bundle.js',
  ],
  executes: () => bun('tgui:build'),
});

export const TguiTscTarget = new Juke.Target({
  dependsOn: [BunTarget],
  executes: () => bun('tgui:tsc'),
});

export const TguiTestTarget = new Juke.Target({
  parameters: [CiParameter],
  dependsOn: [BunTarget],
  executes: () => bun('tgui:test'),
});

export const BiomeCheckTarget = new Juke.Target({
  dependsOn: [BunTarget, BiomeInstallTarget],
  executes: () => bunRoot('tgui:lint'),
});

export const TguiLintTarget = new Juke.Target({
  dependsOn: [BunTarget, BiomeCheckTarget, TguiTscTarget],
});

export const TguiDevTarget = new Juke.Target({
  dependsOn: [BunTarget],
  executes: ({ args }) => bun('tgui:dev', ...args),
});

export const TguiAnalyzeTarget = new Juke.Target({
  dependsOn: [BunTarget],
  executes: () => bun('tgui:analyze'),
});

export const TguiFix = new Juke.Target({
  dependsOn: [BunTarget],
  executes: () => bunRoot('tgui:fix'),
});

export const TestTarget = new Juke.Target({
  dependsOn: [DmTestTarget, TguiTestTarget],
});

export const LintTarget = new Juke.Target({
  dependsOn: [TguiLintTarget],
});

export const BuildTarget = new Juke.Target({
  dependsOn: [TguiTarget, DmTarget],
});

export const ServerTarget = new Juke.Target({
  parameters: [DmVersionParameter, PortParameter],
  dependsOn: [BuildTarget],
  executes: async ({ get }) => {
    const port = get(PortParameter) || '1337';
    const options = {
      dmbFile: `${DME_NAME}.dmb`,
      namedDmVersion: get(DmVersionParameter),
    };
    await DreamDaemon(options, port, '-trusted', '-invisible');
  },
});

export const AllTarget = new Juke.Target({
  dependsOn: [TestTarget, LintTarget, BuildTarget],
});

export const TguiCleanTarget = new Juke.Target({
  executes: async () => {
    Juke.rm('tgui/public/.tmp', { recursive: true });
    Juke.rm('tgui/public/*.map');
    Juke.rm('tgui/public/*.{chunk,bundle,hot-update}.*');
    Juke.rm('tgui/packages/tgfont/dist', { recursive: true });
    Juke.rm('tgui/node_modules', { recursive: true });
    Juke.rm('tgui/packages/*/node_modules', { recursive: true });
  },
});

export const CleanTarget = new Juke.Target({
  dependsOn: [TguiCleanTarget],
  executes: async () => {
    Juke.rm('*.{dmb,rsc}');
    Juke.rm('_maps/templates.dm');
  },
});

/**
 * Removes more junk at the expense of much slower initial builds.
 */
export const CleanAllTarget = new Juke.Target({
  dependsOn: [CleanTarget],
  executes: async () => {
    Juke.logger.info('Cleaning up data/logs');
    Juke.rm('data/logs', { recursive: true });
  },
});

export const TgsTarget = new Juke.Target({
  dependsOn: [TguiTarget],
  executes: async () => {
    Juke.logger.info('Prepending TGS define');
    prependDefines('TGS');
  },
});

Juke.setup({ file: import.meta.url }).then((code) => {
  // We're using the currently available quirk in Juke Build, which
  // prevents it from exiting on Windows, to wait on errors.
  if (code !== 0 && process.argv.includes('--wait-on-error')) {
    Juke.logger.error('Please inspect the error and close the window.');
    return;
  }

  if (TGS_MODE) {
    // workaround for ESBuild process lingering
    // Once https://github.com/privatenumber/esbuild-loader/pull/354 is merged and updated to, this can be removed
    setTimeout(() => process.exit(code), 10000);
  } else {
    process.exit(code);
  }
});

export default TGS_MODE ? TgsTarget : BuildTarget;
