#!/usr/bin/env node

/**
 * Build script for /tg/station 13 codebase.
 *
 * This script uses Juke Build, read the docs here:
 * https://github.com/stylemistake/juke-build
 */

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import Bun from 'bun';
import Juke from './juke/index.js';
import { bun, bunRoot } from './lib/bun';
import { DreamDaemon, DreamMaker, NamedVersionFile } from './lib/byond';
import { downloadFile } from './lib/download';
import { formatDeps } from './lib/helpers';
import { prependDefines } from './lib/tgs';

export const TGS_MODE = process.env.CBT_BUILD_MODE === 'TGS';

// DQEdit — renamed from 'vorestation'
export const DME_NAME = 'deepquarry';

Juke.chdir('../..', import.meta.url);

const dependencies: Record<string, string> = await Bun.file('dependencies.sh')
  .text()
  .then(formatDeps)
  .catch((err) => {
    Juke.logger.error(
      'Failed to read dependencies.sh, please ensure it exists and is formatted correctly.',
    );
    Juke.logger.error(err);
    throw new Juke.ExitCode(1);
  });

// Canonical path for the cutter exe at this moment
function getCutterPath() {
  const ver = dependencies.CUTTER_VERSION;
  const suffix = process.platform === 'win32' ? '.exe' : '';
  const file_ver = ver.split('.').join('-');

  return `tools/icon_cutter/cache/hypnagogic${file_ver}${suffix}`;
}

const cutter_path = getCutterPath();

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

export const ForceRecutParameter = new Juke.Parameter({
  type: 'boolean',
  name: 'force-recut',
});

export const SkipIconCutter = new Juke.Parameter({
  type: 'boolean',
  name: 'skip-icon-cutter',
});

export const WarningParameter = new Juke.Parameter({
  type: 'string[]',
  alias: 'W',
});

export const NoWarningParameter = new Juke.Parameter({
  type: 'string[]',
  alias: 'I',
});

export const CutterTarget = new Juke.Target({
  onlyWhen: () => {
    const files = Juke.glob(cutter_path);
    return files.length === 0;
  },
  executes: async () => {
    const repo = dependencies.CUTTER_REPO;
    const ver = dependencies.CUTTER_VERSION;
    const suffix = process.platform === 'win32' ? '.exe' : '';
    const download_from = `https://github.com/${repo}/releases/download/${ver}/hypnagogic${suffix}`;
    await downloadFile(download_from, cutter_path);
    if (process.platform !== 'win32') {
      await Juke.exec('chmod', ['+x', cutter_path]);
    }
  },
});

export const IconCutterTarget = new Juke.Target({
  parameters: [ForceRecutParameter],
  dependsOn: () => [CutterTarget],
  inputs: () => {
    const standard_inputs = [
      `icons/**/*.png.toml`,
      `icons/**/*.dmi.toml`,
      `cutter_templates/**/*.toml`,
      cutter_path,
    ];
    // Alright we're gonna search out any existing toml files and convert
    // them to their matching .dmi or .png file
    const existing_configs = [
      ...Juke.glob(`icons/**/*.png.toml`),
      ...Juke.glob(`icons/**/*.dmi.toml`),
    ];
    return [
      ...standard_inputs,
      ...existing_configs.map((file) => file.replace('.toml', '')),
    ];
  },
  outputs: ({ get }) => {
    if (get(ForceRecutParameter)) return [];
    const folders = [
      ...Juke.glob(`icons/**/*.png.toml`),
      ...Juke.glob(`icons/**/*.dmi.toml`),
    ];
    return folders
      .map((file) => file.replace(`.png.toml`, '.dmi'))
      .map((file) => file.replace(`.dmi.toml`, '.png'));
  },
  executes: async () => {
    await Juke.exec(cutter_path, [
      '--dont-wait',
      '--templates',
      'cutter_templates',
      'icons',
    ]);
  },
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

// DQAdd Start — build the in-tree verdigris Rust FFI cdylib before the
// server runs. Produces verdigris.dll (Windows) / libverdigris.so (Linux)
// at the repo root, where DreamDaemon loads it via VERDIGRIS_CALL (cave-gen
// + vendored auxmos atmos). The compiled lib is a gitignored per-platform
// artifact, so the build is responsible for producing it.
//
// When cargo IS present: build succeeds or the target throws (hard fail).
// When cargo IS NOT present AND a prebuilt lib exists: warn and skip.
// When cargo IS NOT present AND no prebuilt lib exists: hard fail — a build
//   without the FFI lib would compile but crash at runtime; that's worse
//   than a clear build-time error.
const VERDIGRIS_LIB =
  process.platform === 'win32' ? 'verdigris.dll' : 'libverdigris.so';
const VERDIGRIS_RUST_TARGET =
  process.platform === 'win32'
    ? 'i686-pc-windows-msvc'
    : 'i686-unknown-linux-gnu';

export const VerdigrisTarget = new Juke.Target({
  onlyWhen: () => {
    const probe = spawnSync('cargo', ['--version'], {
      stdio: 'ignore',
      shell: true,
    });
    const cargoOk = !probe.error && probe.status === 0;
    if (!cargoOk) {
      if (fs.existsSync(VERDIGRIS_LIB)) {
        Juke.logger.info(
          `verdigris: cargo not found — using existing ${VERDIGRIS_LIB} (DM-only build)`,
        );
        return false; // skip — prebuilt lib will serve at runtime
      }
      // No cargo and no prebuilt lib: building would produce a runtime-crashing binary.
      Juke.logger.error(
        `verdigris: cargo not found and ${VERDIGRIS_LIB} is missing. `
          + 'Cannot build — atmos/cave-gen FFI will crash at runtime without it. '
          + 'Install rustup (see verdigris/README.md) or obtain a prebuilt '
          + `${VERDIGRIS_LIB} and place it at the repo root.`,
      );
      throw new Juke.ExitCode(1);
    }
    return true;
  },
  inputs: [
    'verdigris/Cargo.toml',
    'verdigris/Cargo.lock',
    'verdigris/verdigris/Cargo.toml',
    'verdigris/verdigris/build.rs',
    'verdigris/verdigris/src/**/*.rs',
    'verdigris/atmos/Cargo.toml',
    'verdigris/atmos/src/**/*.rs',
    'verdigris/atmos/crates/**/Cargo.toml',
    'verdigris/atmos/crates/**/*.rs',
  ],
  outputs: [VERDIGRIS_LIB],
  executes: async () => {
    await Juke.exec(
      'cargo',
      ['build', '--release', '--target', VERDIGRIS_RUST_TARGET],
      { cwd: 'verdigris' },
    );
    fs.copyFileSync(
      `verdigris/target/${VERDIGRIS_RUST_TARGET}/release/${VERDIGRIS_LIB}`,
      VERDIGRIS_LIB,
    );
  },
});
// DQAdd End

// DQAdd Start — regenerate .dmi files from their PNG + .dmi.toml sources
// before DM compile. Architecture A migration: every DMI has editable
// PNG + TOML sources alongside it; this target re-packs them when stale.
//
// inputs/outputs are declared so Juke can validate freshness: when no
// *.dmi.toml or *.png source is newer than any icons/gen/**/*.dmi output
// Juke skips the target entirely, giving a ~0.9s speedup on clean builds.
// build_step.py's own BLAKE2b dirty-check is the authoritative per-file
// gate; Juke's coarser mtime check is the outer skip-entirely gate.
export const IconRepackTarget = new Juke.Target({
  inputs: [
    'icons/**/*.dmi.toml',
    'icons/**/*.png',
    'maps/**/*.dmi.toml',
    'maps/**/*.png',
  ],
  outputs: ['icons/gen/**/*.dmi'],
  executes: async () => {
    await Juke.exec('python3', [
      '-m', 'tools.dq_icons.build_step',
      '--output', 'icons/gen',
      'icons', 'maps',
    ]);
  },
});

// DQAdd — remove all generated DMI files in icons/gen/. Use this when you
// want to force a full repack on the next build (e.g. after hash corruption).
export const CleanIconsTarget = new Juke.Target({
  executes: async () => {
    Juke.logger.info('Removing icons/gen/');
    Juke.rm('icons/gen', { recursive: true });
  },
});
// DQAdd End

// DQAdd Start — validate that every .dm file under code/ is included in
// deepquarry.dme. Runs before the DM compile so missing includes are caught
// with a helpful error rather than silently-uncompiled code.
export const ValidateDmeTarget = new Juke.Target({
  inputs: ['code/**/*.dm', `${DME_NAME}.dme`],
  executes: async () => {
    const dmeContent = fs.readFileSync(`${DME_NAME}.dme`, 'utf-8');

    // Build the set of all paths mentioned in the DME (normalise to forward-slash).
    const mentioned = new Set<string>();
    for (const match of dmeContent.matchAll(/#include\s+"([^"]+\.dm)"/g)) {
      mentioned.add(match[1].replace(/\\/g, '/'));
    }
    // Also collect commented-out includes (DQRemoved / disabled lines) so we
    // don't false-positive on intentionally-disabled files.
    const disabled = new Set<string>();
    for (const match of dmeContent.matchAll(/\/\/\s*(?:DQRemoved:?\s*)?#include\s+"([^"]+\.dm)"/g)) {
      disabled.add(match[1].replace(/\\/g, '/'));
    }

    const dmFiles = Juke.glob('code/**/*.dm');
    const missing: string[] = [];
    for (const file of dmFiles) {
      const normalized = file.replace(/\\/g, '/');
      if (!mentioned.has(normalized) && !disabled.has(normalized)) {
        missing.push(normalized);
      }
    }

    if (missing.length > 0) {
      Juke.logger.error(
        `${missing.length} .dm file(s) under code/ are not included in ${DME_NAME}.dme:\n` +
        missing.map((f) => `  ${f}`).join('\n') +
        '\n\nAdd each file to deepquarry.dme or comment it out with // DQRemoved: #include "..."',
      );
      throw new Juke.ExitCode(1);
    }
    Juke.logger.info(`ValidateDme: all ${dmFiles.length} code/ .dm files are included.`);
  },
});
// DQAdd End

export const DmTarget = new Juke.Target({
  parameters: [
    DefineParameter,
    DmVersionParameter,
    WarningParameter,
    NoWarningParameter,
    SkipIconCutter,
  ],
  dependsOn: ({ get }) => [
    get(DefineParameter).includes('ALL_MAPS') && DmMapsIncludeTarget,
    !get(SkipIconCutter) && IconCutterTarget,
    IconRepackTarget, // DQAdd — regenerate .dmi from PNG+TOML before DM compile
    ValidateDmeTarget, // DQAdd — fail fast if any code/ .dm is missing from the DME
    DreamCheckerTarget, // DQAdd — run SpacemanDMM lint before DM compile if available
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
    'modular_chomp/**', // CHOMPAdd
    'modular_dq/**', // DQAdd — without this, edits to fork code don't invalidate the DM build cache
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
    IconCutterTarget,
    IconRepackTarget, // DQAdd — tests boot the world, which uses the .rsc
    ValidateDmeTarget, // DQAdd — catch missing includes before compiling
    VerdigrisTarget, // DQAdd — tests boot the world, which loads the FFI lib
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
    IconCutterTarget,
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

// DQAdd Start — run SpacemanDMM dreamchecker before the DM compile if the
// binary is available. Best-effort: if dreamchecker is not on PATH the target
// no-ops with a warning. CI installs it via tools/ci/install_spaceman_dmm.sh;
// local dev can skip it without consequence.
export const DreamCheckerTarget = new Juke.Target({
  inputs: ['code/**/*.dm', 'deepquarry.dme'],
  onlyWhen: () => {
    const probe = spawnSync('dreamchecker', ['--version'], {
      stdio: 'ignore',
      shell: true,
    });
    if (probe.error || probe.status !== 0) {
      Juke.logger.info('dreamchecker not found on PATH — skipping DM lint (install via tools/ci/install_spaceman_dmm.sh)');
      return false;
    }
    return true;
  },
  executes: async () => {
    await Juke.exec('dreamchecker', [`${DME_NAME}.dme`]);
  },
});
// DQAdd End

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
  dependsOn: [TguiLintTarget, DreamCheckerTarget], // DQAdd — DM lint via SpacemanDMM if available
});

export const BuildTarget = new Juke.Target({
  dependsOn: [TguiTarget, DmTarget, VerdigrisTarget], // DQAdd — verdigris FFI lib
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
  dependsOn: [TguiCleanTarget, CleanIconsTarget], // DQAdd — also remove icons/gen/
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
