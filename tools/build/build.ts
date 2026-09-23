#!/usr/bin/env node

/**
 * Build script for /tg/station 13 codebase.
 *
 * This script uses Juke Build, read the docs here:
 * https://github.com/stylemistake/juke-build
 */

import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import Juke from './juke/index.js';
import { bun, bunRoot } from './lib/bun';
import { acquireDdSlot } from './lib/dd_slot';
import { generateVerdigrisBindings } from './lib/verdigris_bindings';
import {
  BENCH_RUNS_DIR,
  type BenchIteration,
  type BenchRun,
  compareRuns,
  formatComparison,
  formatNumber,
  listRuns,
  type ProcessSample,
  ProcessSampler,
  type ProcessSummary,
  readJson,
  resolveRun,
  runIdentity,
  summarize,
  TEST_RUNS_DIR,
  type TestRun,
  testHotspots,
  testRunRecord,
  type UnitTestEntry,
  type WorldBenchDocument,
  writeJson,
} from './lib/bench';
import { renderReport } from './lib/bench_report';
import { DreamDaemon, DreamMaker, NamedVersionFile } from './lib/byond';
import { prependDefines } from './lib/tgs';
import { MAP_BOUNDS_FILE, writeMapBounds } from './lib/map_bounds';

export const TGS_MODE = process.env.CBT_BUILD_MODE === 'TGS';

// DQEdit — renamed from 'vorestation'
export const DME_NAME = 'deepquarry';

function findDreamChecker(): string | null {
  const candidates = [
    process.env.DREAMCHECKER_EXE,
    'dreamchecker',
    process.env.USERPROFILE
      ? `${process.env.USERPROFILE}\\SpacemanDMM\\dreamchecker.exe`
      : null,
  ].filter((candidate): candidate is string => !!candidate);

  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ['--version'], {
      stdio: 'ignore',
      shell: candidate === 'dreamchecker',
    });
    if (!probe.error && probe.status === 0) {
      return candidate;
    }
  }
  return null;
}

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
// inputs/outputs are declared so Juke can validate freshness: when no
// *.dmi.toml or *.png source is newer than any icons/gen/**/*.dmi output
// Juke skips the target entirely, giving a ~0.9s speedup on clean builds.
// build_step.py's own BLAKE2b dirty-check is the authoritative per-file
// gate; Juke's coarser mtime check is the outer skip-entirely gate.
export const IconRepackTarget = new Juke.Target({
  // No Juke inputs/outputs: build_step.py does its own BLAKE2b dirty-check, and
  // declaring an 'icons/gen/**/*.dmi' output makes Juke try to touch outputs
  // that may not exist yet, crashing the build. Let the python step gate itself.
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

// Width/height of every .dmm, so map templates aren't parsed at boot just to
// learn their size (doc/rewrite/fixes.md Q2). DM falls back to parsing when an
// entry is missing or the file's size changed.
export const MapBoundsTarget = new Juke.Target({
  inputs: ['maps/**/*.dmm'],
  outputs: [MAP_BOUNDS_FILE],
  executes: async () => {
    const count = writeMapBounds(['maps']);
    Juke.logger.info(`Wrote bounds for ${count} maps to ${MAP_BOUNDS_FILE}`);
  },
});

// DQAdd Start — validate that every .dm file under code/ is included in
// deepquarry.dme. Runs before the DM compile so missing includes are caught
// with a helpful error rather than silently-uncompiled code.
export const ValidateDmeTarget = new Juke.Target({
  inputs: ['code/**/*.dm', `${DME_NAME}.dme`],
  executes: async () => {
    // A .dm file is "compiled" if it is reachable from the .dme through the
    // transitive #include graph — NOT just if it appears literally in the .dme.
    // Many files are pulled in by intermediate aggregators (e.g.
    // code/modules/tgs/includes.dm includes its core/v5 subfiles; code/__odlint.dm
    // includes __pragmas.dm). A naive "is it in the .dme" check false-positives
    // on every such transitively-included file, so we walk the graph.
    //
    // #include paths in the .dme are relative to the repo root; #include paths
    // inside a .dm file are relative to that file's own directory. Both may use
    // either slash style.

    // Resolve an #include target to a repo-root-relative, forward-slash path.
    const resolveInclude = (baseDir: string, raw: string): string => {
      const combined = baseDir === '.' ? raw : `${baseDir}/${raw}`;
      const out: string[] = [];
      for (const seg of combined.replace(/\\/g, '/').split('/')) {
        if (seg === '' || seg === '.') continue;
        if (seg === '..') { out.pop(); continue; }
        out.push(seg);
      }
      return out.join('/');
    };
    const dirOf = (file: string): string => {
      const i = file.lastIndexOf('/');
      return i === -1 ? '.' : file.slice(0, i);
    };

    const ACTIVE_INCLUDE = /^[ \t]*#include\s+"([^"]+\.dm)"/gm;
    const COMMENTED_INCLUDE = /^[ \t]*\/\/\s*#include\s+"([^"]+\.dm)"/gm;

    const reachable = new Set<string>();  // compiled (transitively included)
    const disabled = new Set<string>();   // intentionally commented-out includes
    const queue: string[] = [];

    const seed = (content: string, baseDir: string) => {
      for (const m of content.matchAll(ACTIVE_INCLUDE)) {
        queue.push(resolveInclude(baseDir, m[1]));
      }
      for (const m of content.matchAll(COMMENTED_INCLUDE)) {
        disabled.add(resolveInclude(baseDir, m[1]));
      }
    };

    seed(fs.readFileSync(`${DME_NAME}.dme`, 'utf-8'), '.');
    while (queue.length > 0) {
      const file = queue.pop() as string;
      if (reachable.has(file)) continue;
      reachable.add(file);
      if (!fs.existsSync(file)) continue; // missing include target: DM compile will report it
      seed(fs.readFileSync(file, 'utf-8'), dirOf(file));
    }

    // Unit-test files are compiled only under a separate test .dme, never from
    // deepquarry.dme — exclude them from the "is it wired into the build" check.
    const EXCLUDED_PREFIXES = [
      'code/modules/unit_tests/',
    ];

    const dmFiles = Juke.glob('code/**/*.dm');
    const missing: string[] = [];
    for (const file of dmFiles) {
      const normalized = file.replace(/\\/g, '/');
      if (reachable.has(normalized) || disabled.has(normalized)) continue;
      if (EXCLUDED_PREFIXES.some((p) => normalized.startsWith(p))) continue;
      missing.push(normalized);
    }

    if (missing.length > 0 && (process.env.DQ_WIP_TREE || process.env.DQ_ALLOW_UNREACHABLE_DM)) {
      Juke.logger.warn(
        `DQ_WIP_TREE is set: ignoring ${missing.length} .dm file(s) not reachable from ${DME_NAME}.dme:\n`
        + missing.map((f) => `  ${f}`).join('\n'),
      );
      return;
    }
    if (missing.length > 0) {
      Juke.logger.error(
        `${missing.length} .dm file(s) under code/ are not reachable from ${DME_NAME}.dme `
          + 'via the #include graph (silently uncompiled):\n'
        + missing.map((f) => `  ${f}`).join('\n')
        + '\n\nAdd each file to deepquarry.dme (or an included aggregator), or delete it if unused.',
      );
      throw new Juke.ExitCode(1);
    }
    Juke.logger.info(`ValidateDme: all ${dmFiles.length} code/ .dm files are reachable from the DME.`);
  },
});
// DQAdd End

// DQAdd Start — build the in-tree verdigris Rust FFI cdylib before the
// server runs. Produces verdigris.dll (Windows) / libverdigris.so (Linux)
// at the repo root, where DreamDaemon loads it via the generated vg_* bindings (cave-gen
// + vendored auxmos atmos). The compiled lib is a gitignored per-platform
// artifact, so the build is responsible for producing it.
//
// onlyWhen gates on cargo being on PATH: DM-only contributors without rustup
// can't build the lib (they warn-skip and run with whatever lib is present —
// atmos/cave-gen FFI simply isn't available without it). inputs/outputs
// dirty-checks the ~minute cargo build against the Rust sources so untouched
// rebuilds no-op. Source paths are enumerated rather than `verdigris/**` so
// the (un-gitignored-by-Glob) verdigris/target/ build dir doesn't count as
// input and force a perpetual rebuild.
const VERDIGRIS_LIB =
  process.platform === 'win32' ? 'verdigris.dll' : 'libverdigris.so';
const VERDIGRIS_RUST_TARGET =
  process.platform === 'win32'
    ? 'i686-pc-windows-msvc'
    : 'i686-unknown-linux-gnu';

// DQAdd Start — generated DM bindings for verdigris (doc/rewrite/rust_core.md §9).
// `verdigris-bindings` rewrites code/__defines/verdigris/_bindings.dm and
// verdigris/ffi/src/abi.rs from the #[auxmacros::bind] functions. Every DM and
// DLL build runs the check first and fails when either file is stale.
export const VerdigrisBindingsTarget = new Juke.Target({
  executes: () => {
    const written = generateVerdigrisBindings(process.cwd(), false);
    Juke.logger.info(
      written.length ? `verdigris bindings: wrote ${written.join(', ')}` : 'verdigris bindings: up to date',
    );
  },
});

export const VerdigrisBindingsCheckTarget = new Juke.Target({
  executes: () => {
    const stale = generateVerdigrisBindings(process.cwd(), true);
    if (stale.length) {
      Juke.logger.error(
        `verdigris bindings are stale (${stale.join(', ')}). `
          + 'Run `tools/build/build.sh verdigris-bindings` and commit the result.',
      );
      throw new Juke.ExitCode(1);
    }
  },
});
// DQAdd End

export const VerdigrisTarget = new Juke.Target({
  dependsOn: [VerdigrisBindingsCheckTarget],
  onlyWhen: () => {
    // DM-only work (agents in worktrees, CI lint jobs) can reuse a prebuilt
    // library instead of compiling the whole Rust workspace.
    if (process.env.DQ_PREBUILT_VERDIGRIS === '1' && fs.existsSync(VERDIGRIS_LIB)) {
      Juke.logger.info(`verdigris: DQ_PREBUILT_VERDIGRIS=1 — using existing ${VERDIGRIS_LIB}`);
      return false;
    }
    const probe = spawnSync('cargo', ['--version'], {
      stdio: 'ignore',
      shell: true,
    });
    const cargoOk = !probe.error && probe.status === 0;
    if (!cargoOk) {
      if (fs.existsSync(VERDIGRIS_LIB)) {
        Juke.logger.info(
          `verdigris: cargo not found — using existing ${VERDIGRIS_LIB}`,
        );
      } else {
        Juke.logger.warn(
          `verdigris: cargo not found and ${VERDIGRIS_LIB} is missing. `
            + 'Atmos/cave-gen FFI will fail at runtime — install rustup '
            + `(see verdigris/README.md) or obtain a prebuilt ${VERDIGRIS_LIB}.`,
        );
      }
      return false;
    }
    return true;
  },
  inputs: [
    'verdigris/Cargo.toml',
    'verdigris/Cargo.lock',
    'verdigris/core/**/Cargo.toml',
    'verdigris/core/**/build.rs',
    'verdigris/core/**/*.rs',
    'verdigris/domains/**/Cargo.toml',
    'verdigris/domains/**/build.rs',
    'verdigris/domains/**/*.rs',
    'verdigris/ffi/**/Cargo.toml',
    'verdigris/ffi/**/build.rs',
    'verdigris/ffi/**/*.rs',
    'verdigris/verdigris/**/Cargo.toml',
    'verdigris/verdigris/**/build.rs',
    'verdigris/verdigris/**/*.rs',
    'verdigris/tools/**/Cargo.toml',
    'verdigris/tools/**/build.rs',
    'verdigris/tools/**/*.rs',
  ],
  outputs: [VERDIGRIS_LIB],
  executes: async () => {
    await Juke.exec(
      'cargo',
      ['build', '--release', '--target', VERDIGRIS_RUST_TARGET],
      { cwd: 'verdigris' },
    );
    fs.copyFileSync(
      `${process.env.CARGO_TARGET_DIR || 'verdigris/target'}/${VERDIGRIS_RUST_TARGET}/release/${VERDIGRIS_LIB}`,
      VERDIGRIS_LIB,
    );
  },
});
// DQAdd End

// DreamDaemon security for test, bench and run worlds. -trusted makes BYOND show a
// "Proceed with trusted mode?" dialog for any .dmb path it hasn't been told to
// trust, which hangs headless runs in new worktrees forever. DQ_DD_SECURITY=safe
// runs without it (safe mode still allows files and DLLs inside the world folder).
// Test, bench and autowiki worlds default to safe; the server keeps trusted.
const ddSecurityFlag = (fallback = 'safe') => `-${process.env.DQ_DD_SECURITY || fallback}`;

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
    ValidateDmeTarget, // DQAdd — fail fast if any code/ .dm is missing from the DME
    VerdigrisBindingsCheckTarget, // DQAdd — _bindings.dm must match the Rust binds
    DreamCheckerTarget, // DQAdd — run SpacemanDMM lint before DM compile if available
    MapBoundsTarget, // boot reads template sizes from data/map_template_bounds.json
  ],
  inputs: [
    '_maps/map_files/generic/**',
    'maps/**/*.dm',
    'maps/**/*.dmm',
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

// ---------------------------------------------------------------------------
// Unit tests, benchmarks and their records. doc/testing.md is the user guide;
// lib/bench.ts holds the storage, statistics and comparison logic.

export const RunsParameter = new Juke.Parameter({ type: 'number' });
export const WarmupParameter = new Juke.Parameter({ type: 'number' });
export const ScenarioParameter = new Juke.Parameter({ type: 'string[]', alias: 's' });
export const ArgParameter = new Juke.Parameter({ type: 'string[]' });
export const ProfileParameter = new Juke.Parameter({ type: 'boolean' });
export const LabelParameter = new Juke.Parameter({ type: 'string' });
/** `dm-test --shards=N`: boots N DreamDaemon worlds instead of one. See doc/testing.md "Sharded sweeps". */
export const ShardsParameter = new Juke.Parameter({ type: 'number' });
export const BaseParameter = new Juke.Parameter({ type: 'string' });
export const HeadParameter = new Juke.Parameter({ type: 'string' });
export const ThresholdParameter = new Juke.Parameter({ type: 'number' });
export const FailOnRegressionParameter = new Juke.Parameter({ type: 'boolean' });
export const AllParameter = new Juke.Parameter({ type: 'boolean' });
export const RefParameter = new Juke.Parameter({ type: 'string' });

/** Set in a tree with unfinished work to tolerate dangling or missing includes. */
const WIP_TREE = !!(process.env.DQ_WIP_TREE || process.env.DQ_ALLOW_UNREACHABLE_DM);

/**
 * Writes the manifest for a test or benchmark build. In a WIP tree
 * (DQ_WIP_TREE=1), includes whose file no longer exists are dropped with a
 * warning so half-finished work elsewhere doesn't block verification.
 */
function writeDerivedDme(target: string): void {
  let text = fs.readFileSync(`${DME_NAME}.dme`, 'utf-8');
  if (WIP_TREE) {
    const dropped: string[] = [];
    text = text
      .split(/\r?\n/)
      .filter((line) => {
        const match = /^#include "(.+)"/.exec(line.trim());
        if (match && !fs.existsSync(match[1].replace(/\\/g, '/'))) {
          dropped.push(match[1]);
          return false;
        }
        return true;
      })
      .join('\n');
    if (dropped.length) {
      Juke.logger.warn(`DQ_WIP_TREE: dropped ${dropped.length} include(s) of missing files:\n${dropped.map((f) => `  ${f}`).join('\n')}`);
    }
  }
  fs.writeFileSync(target, text);
}

// Where compileDerived() records the content hash it compiled a .dmb/.rsc
// pair from, so a later call (a rerun on an unchanged tree: flake reruns,
// focused reruns) can skip DreamMaker() entirely. Lives under data/, so it's
// per-worktree like everything else there -- never shared between worktrees.
const DMB_CACHE_DIR = 'data/dmb-cache';

/**
 * The .dm files transitively #include'd from `dmeText` (paths relative to
 * the repo root). A small, self-contained walk of the same #include graph
 * ValidateDmeTarget checks, kept separate (rather than shared) so this cache
 * addition stays a minimal, independent diff.
 */
function resolveDmeIncludes(dmeText: string): string[] {
  const resolveInclude = (baseDir: string, raw: string): string => {
    const combined = baseDir === '.' ? raw : `${baseDir}/${raw}`;
    const out: string[] = [];
    for (const seg of combined.replace(/\\/g, '/').split('/')) {
      if (seg === '' || seg === '.') continue;
      if (seg === '..') { out.pop(); continue; }
      out.push(seg);
    }
    return out.join('/');
  };
  const dirOf = (file: string): string => {
    const i = file.lastIndexOf('/');
    return i === -1 ? '.' : file.slice(0, i);
  };
  const ACTIVE_INCLUDE = /^[ \t]*#include\s+"([^"]+\.dm)"/gm;
  const reachable = new Set<string>();
  const queue: string[] = [];
  const seed = (content: string, baseDir: string) => {
    for (const m of content.matchAll(ACTIVE_INCLUDE)) {
      queue.push(resolveInclude(baseDir, m[1]));
    }
  };
  seed(dmeText, '.');
  while (queue.length > 0) {
    const file = queue.pop() as string;
    if (reachable.has(file)) continue;
    reachable.add(file);
    if (!fs.existsSync(file)) continue; // missing include: DreamMaker will report it
    seed(fs.readFileSync(file, 'utf-8'), dirOf(file));
  }
  return [...reachable].sort();
}

/**
 * Content hash of everything that determines a derived-dme compile's
 * output: the derived .dme text itself, the full content of every .dm file
 * it transitively includes, the define list, and the DM compiler version.
 * Order-independent in the define list; file order is fixed (sorted) so the
 * hash is stable across runs.
 */
function computeCompileHash(dmeText: string, defines: string[], dmVersion: string | null): string {
  const hash = createHash('sha256');
  hash.update(dmeText);
  for (const file of resolveDmeIncludes(dmeText)) {
    hash.update(file);
    try {
      hash.update(fs.readFileSync(file));
    } catch {
      hash.update('<unreadable>');
    }
  }
  hash.update(JSON.stringify([...defines].sort()));
  hash.update(dmVersion ?? '');
  return hash.digest('hex');
}

async function compileDerived(dme: string, get: any, defines: string[]): Promise<void> {
  writeDerivedDme(dme);
  const dmeText = fs.readFileSync(dme, 'utf-8');
  const allDefines = [...defines, ...get(DefineParameter)];
  const dmVersion = get(DmVersionParameter);
  const dmbFile = dme.replace(/\.dme$/, '.dmb');
  const rscFile = dme.replace(/\.dme$/, '.rsc');
  const cacheFile = `${DMB_CACHE_DIR}/${path.basename(dme)}.hash.json`;
  const hash = computeCompileHash(dmeText, allDefines, dmVersion);
  if (fs.existsSync(dmbFile) && fs.existsSync(rscFile)) {
    try {
      const cached = JSON.parse(fs.readFileSync(cacheFile, 'utf-8'));
      if (cached.hash === hash) {
        Juke.logger.info(`compileDerived: reusing ${dmbFile} (compile inputs unchanged since ${cached.compiledAt}).`);
        return;
      }
    } catch {
      // No cache record yet, or it's unreadable/stale-format: fall through and recompile.
    }
  }
  try {
    await DreamMaker(dme, {
      defines: allDefines,
      warningsAsErrors: get(WarningParameter).includes('error'),
      ignoreWarningCodes: get(NoWarningParameter),
      namedDmVersion: dmVersion,
    });
  } catch (error) {
    // Don't leave a half-built derived dme/rsc lying around after a failed compile.
    await removeDerivedArtifacts(dme.replace(/\.dme$/, '.*'));
    try {
      fs.rmSync(cacheFile, { force: true });
    } catch {
      // best-effort
    }
    throw error;
  }
  fs.mkdirSync(DMB_CACHE_DIR, { recursive: true });
  writeJson(cacheFile, { hash, defines: allDefines, dmVersion, compiledAt: new Date().toISOString() });
}

type WorldRun = {
  clean: boolean;
  cleanText: string | null;
  results: Record<string, UnitTestEntry> | null;
  durationSeconds: number;
  process: ProcessSummary | null;
  samples: ProcessSample[];
  /** TRUE when the DreamDaemon watchdog had to force-kill this world for
   * still running past its hard timeout (as opposed to the routine
   * post-completion zombie cleanup) -- see DDResult.killedByWatchdog. Its
   * results are likely missing or incomplete; always logged as an explicit
   * error rather than folded into an ordinary "not clean". */
  killedByWatchdog: boolean;
};

/**
 * Boots a compiled test/bench world once and collects what it wrote. The
 * world signals completion by writing data/unit_tests.json; the watchdog
 * reaps daemons that linger afterwards (common on Windows).
 */
async function runTestWorld(
  dmbFile: string,
  dmVersion: string | null,
  worldParams: Record<string, string>,
  sample: boolean,
): Promise<WorldRun> {
  Juke.rm('data/logs/ci', { recursive: true });
  Juke.rm('data/unit_tests.json');
  Juke.rm('data/bench/process.json');
  Juke.rm('data/bench/scenarios.json');
  fs.mkdirSync('data/bench', { recursive: true });
  const sampler = sample ? new ProcessSampler('data/bench/process.json') : null;
  const params = new URLSearchParams({ 'log-directory': 'ci', ...worldParams }).toString();
  const started = Date.now();
  let killedByWatchdog = false;
  try {
    const result = await DreamDaemon(
      {
        dmbFile,
        namedDmVersion: dmVersion,
        watchdogFile: 'data/unit_tests.json',
        onSpawn: (pid) => sampler?.start(pid),
      },
      '-close',
      ddSecurityFlag(),
      '-verbose',
      '-params',
      params,
    );
    killedByWatchdog = !!result.killedByWatchdog;
  } catch {
    // DreamDaemon exits non-zero even on clean runs; the files below decide.
  }
  const processSummary = sampler ? sampler.stop() : null;
  let cleanText: string | null = null;
  try {
    cleanText = fs.readFileSync('data/logs/ci/clean_run.lk', 'utf-8');
  } catch {
    // not clean
  }
  let results: Record<string, UnitTestEntry> | null = null;
  try {
    results = JSON.parse(fs.readFileSync('data/unit_tests.json', 'utf-8'));
  } catch {
    // the world died before finishing
  }
  return {
    clean: cleanText !== null,
    cleanText,
    results,
    durationSeconds: (Date.now() - started) / 1000,
    process: processSummary,
    samples: sampler?.samples ?? [],
    killedByWatchdog,
  };
}

function printLogTails(): void {
  for (const logFile of ['data/logs/ci/tests.log', 'data/logs/ci/runtime.log']) {
    if (!fs.existsSync(logFile)) continue;
    const lines = fs.readFileSync(logFile, 'utf-8').trim().split(/\r?\n/);
    Juke.logger.error(`Last output from ${logFile}:`);
    console.error(lines.slice(-80).join('\n'));
  }
}

/** Best-effort removal of build copies; DreamDaemon can hold the .rsc briefly. */
async function removeDerivedArtifacts(pattern: string): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      Juke.rm(pattern);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }
  Juke.logger.warn(`Could not remove ${pattern}; it will be replaced on the next run.`);
}

function reportFocus(): void {
  const focusedTests = fs
    .readFileSync('code/modules/unit_tests/dq_focus.dm', 'utf-8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith('TEST_FOCUS('));
  if (focusedTests.length) {
    Juke.logger.warn(`Focused unit-test run (${focusedTests.length}): ${focusedTests.join(', ')}`);
  } else {
    Juke.logger.info('Full unit-test suite selected.');
  }
}

/** Stores a test run under data/test-runs/ and prints its summary. */
function recordTestRun(run: WorldRun, label: string | null, defines: string[]): TestRun | null {
  if (run.killedByWatchdog) {
    Juke.logger.error(
      'Unit-test summary: the DreamDaemon watchdog force-killed this world for running past its hard '
        + `timeout (DQ_DD_WATCHDOG_MINUTES to raise it). ${run.results ? 'Partial' : 'No'} results were captured.`,
    );
  }
  if (!run.results) return null;
  const record = testRunRecord(runIdentity(label), label, defines, run.clean, run.durationSeconds, run.results);
  writeJson(`${TEST_RUNS_DIR}/${record.id}.json`, record);
  Juke.logger.info(
    `Unit-test summary: ${record.counts.passed} passed, ${record.counts.failed} failed, ${record.counts.skipped} skipped `
      + `in ${Math.round(record.duration_seconds)}s (saved ${TEST_RUNS_DIR}/${record.id}.json).`,
  );
  console.log(testHotspots(run.results, 20));
  for (const name of record.failed) {
    Juke.logger.error(`FAILED ${name}: ${run.results[name].message ?? ''}`);
  }
  return record;
}

const TEST_DEFINES = ['CBT', 'CIBUILDING', 'CITESTING'];

// ---------------------------------------------------------------------------
// Domains, tiers and `--affected` (`dm-test --domains=a,b`, `--tier=fast`,
// `--affected`). See doc/testing.md "Domains, tiers and --affected".
//
// This is a lightweight, best-effort classifier: a file/path keyword ->
// domain table, not a hand-maintained per-test registry. It's meant to
// shrink "which tests should I run for this change" from "the whole suite"
// to "probably these", not to be authoritative -- a domain-filtered or
// --affected run is for fast local iteration; CI and the merge-to-master run
// always use --full (no filter at all).

/** Path/filename keyword -> domain, first match wins (most specific first).
 * Checked against both unit-test file paths (to tag a test) and changed
 * source file paths (for --affected). Unmatched -> domain "misc". */
const DOMAIN_PATTERNS: [RegExp, string][] = [
  [/atmos/i, 'atmos'],
  [/\bheat\b|thermal/i, 'heat'],
  [/\bpower\b|reactor|solars?|smes|electric/i, 'power'],
  [/contain(ment|er)/i, 'containment'],
  [/\binteraction\b/i, 'interaction'],
  [/medical|surgery|disease|genetics|\borgan\b|\bbody\b|physiology|stabilisation|diagnosis/i, 'medical'],
  [/vore|belly/i, 'vore'],
  [/\brule/i, 'rules'],
  [/\bstate\b|latent/i, 'state'],
  [/\bmob\b|\blife\b|hibernat/i, 'mobs'],
  [/tgui|\bui_|interface/i, 'ui'],
  [/construction|assembly|\bmech\b/i, 'construction'],
  [/combat|weapon|armor|armour|melee/i, 'combat'],
  [/expedition|flight_operations|generated_station/i, 'expedition'],
  [/material/i, 'materials'],
  [/economy|\bstock\b|contract/i, 'economy'],
];

function classifyDomain(filePath: string): string {
  const normalized = filePath.replace(/\\/g, '/');
  for (const [pattern, domain] of DOMAIN_PATTERNS) {
    if (pattern.test(normalized)) return domain;
  }
  return 'misc';
}

/** Every declared unit-test type, the file it's declared in, and its
 * inferred domain -- a source scan (see enumerateUnitTestTypes()'s doc), not
 * a world boot. */
function enumerateUnitTestsWithDomain(): { name: string; file: string; domain: string }[] {
  const TYPE_DECL = /^\/datum\/unit_test\/[A-Za-z0-9_/]+$/;
  const out: { name: string; file: string; domain: string }[] = [];
  for (const file of Juke.glob('code/modules/unit_tests/*.dm')) {
    const domain = classifyDomain(file);
    for (const line of fs.readFileSync(file, 'utf-8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (TYPE_DECL.test(trimmed)) out.push({ name: trimmed, file, domain });
    }
  }
  return out;
}

/** Files changed since the merge-base with master (falls back to the working
 * tree's own uncommitted changes if there's no `master` ref to diff
 * against -- e.g. a shallow clone). */
function changedFiles(): string[] {
  const run = (args: string[]) => spawnSync('git', args, { encoding: 'utf-8', cwd: process.cwd() });
  const base = run(['merge-base', 'master', 'HEAD']);
  if (base.status === 0) {
    const diff = run(['diff', '--name-only', base.stdout.trim()]);
    if (diff.status === 0) return diff.stdout.split(/\r?\n/).filter(Boolean);
  }
  const status = run(['status', '--porcelain']);
  if (status.status === 0) {
    return status.stdout
      .split(/\r?\n/)
      .filter(Boolean)
      .map((line) => line.slice(3).trim());
  }
  return [];
}

/** Domains touched by files changed since master (or the working tree, as a
 * fallback -- see changedFiles()). Empty only when nothing changed or git
 * itself is unavailable; the caller falls back to the full suite in that case
 * rather than silently running nothing. */
function affectedDomains(): Set<string> {
  const domains = new Set<string>();
  for (const file of changedFiles()) domains.add(classifyDomain(file));
  return domains;
}

export const DomainsParameter = new Juke.Parameter({ type: 'string[]' });
export const TierParameter = new Juke.Parameter({ type: 'string' });
export const AffectedParameter = new Juke.Parameter({ type: 'boolean' });

/** Resolves --domains/--tier/--affected into an explicit test selection (null
 * = no filter, run everything), and reports what it picked. `--tier=sweep`
 * selects only the type-sweep tests; `--tier=fast` (default) excludes them;
 * `--domains=a,b` (any tier) keeps only tests in those domains; `--affected`
 * unions in every domain touched by changed files. Combining `--affected`
 * with explicit `--domains` unions both. */
function resolveTestSelection(get: any): string[] | null {
  const tierRaw = get(TierParameter) as string | null;
  const explicitDomains = new Set(get(DomainsParameter) as string[]);
  const affected = get(AffectedParameter) as boolean;
  // No --tier/--domains/--affected at all: run everything, unfiltered. This
  // must stay a real "no filter" (return null, not a computed full list) --
  // a plain `dm-test`/`dm-test --shards=N` with no flags is the default path
  // every existing caller (CI, the merge-to-master run, dq_focused_test.sh)
  // uses, and it must never silently drop tests.
  if (!tierRaw && !explicitDomains.size && !affected) return null;
  const tier = tierRaw ?? 'fast';

  const domains = new Set(explicitDomains);
  if (affected) {
    const touched = affectedDomains();
    if (!touched.size) {
      Juke.logger.warn('--affected: no changed files found against master; falling back to --tier only.');
    }
    for (const d of touched) domains.add(d);
  }

  const includeSweeps = tier === 'sweep' || tier === 'full';
  const includeNonSweeps = tier !== 'sweep';
  const all = enumerateUnitTestsWithDomain();
  const selected = all
    .filter((t) => (SWEEP_TEST_NAMES.has(t.name) ? includeSweeps : includeNonSweeps))
    .filter((t) => (domains.size ? domains.has(t.domain) : true))
    .map((t) => t.name);

  Juke.logger.info(
    `Test selection: tier=${tier}${domains.size ? `, domains=${[...domains].join(',')}` : ''} `
      + `-> ${selected.length}/${all.length} test(s).`,
  );
  return selected;
}

// ---------------------------------------------------------------------------
// Sharded dm-test (`dm-test --shards=N`): one compile, N DreamDaemon worlds,
// merged into one result. See doc/testing.md "Sharded sweeps".

/**
 * Type-sweep tests, excluded from the bin-packer below: sweep_types()
 * already spreads each one's cost evenly across every shard's world, so
 * pinning one to a single shard (as if it were a normal test) would both
 * double-count its historical duration in that shard's load estimate and
 * under-count it everywhere else. Keep this in sync with each test's
 * `is_sweep_test = TRUE` in code/modules/unit_tests/*.dm.
 */
const SWEEP_TEST_NAMES = new Set([
  '/datum/unit_test/dq_lifecycle_sandbox',
  '/datum/unit_test/dq_state_latent_round_trip',
  '/datum/unit_test/dq_property_type_values_valid',
  '/datum/unit_test/all_clothing_shall_be_valid',
  '/datum/unit_test/dq_constraint_parity/equip',
  '/datum/unit_test/dq_constraint_parity/storage',
  '/datum/unit_test/dq_constraint_parity/suit_storage',
  '/datum/unit_test/dq_constraint_parity/holster',
]);

const SHARD_DIR = 'data/test-shards';

/** Every `/datum/unit_test/...` type declared under code/modules/unit_tests,
 * by scanning source (a bare `/datum/unit_test/foo` line, not a proc/var
 * line under it) rather than booting a world -- used to seed shard
 * assignment for tests with no historical duration yet (new tests, or a
 * fresh checkout with no data/test-runs/ history). */
function enumerateUnitTestTypes(): string[] {
  const TYPE_DECL = /^\/datum\/unit_test\/[A-Za-z0-9_/]+$/;
  const names: string[] = [];
  for (const file of Juke.glob('code/modules/unit_tests/*.dm')) {
    for (const line of fs.readFileSync(file, 'utf-8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (TYPE_DECL.test(trimmed)) names.push(trimmed);
    }
  }
  return names;
}

/** Greedy bin-packing of every known non-sweep test onto `shardCount`
 * shards by historical duration (from the latest stored test run, if any),
 * heaviest first onto the currently lightest shard. Tests with no
 * historical record get a small default weight, so new tests still balance
 * instead of piling onto shard 0. */
function assignTestShards(shardCount: number, selection: Set<string> | null): string[][] {
  const shards: string[][] = Array.from({ length: shardCount }, () => []);
  const loads = new Array(shardCount).fill(0);
  const durations = new Map<string, number>();
  const runs = listRuns(TEST_RUNS_DIR);
  if (runs.length) {
    const latest = readJson<TestRun>(runs[runs.length - 1]);
    for (const [name, entry] of Object.entries(latest.tests)) {
      if (!SWEEP_TEST_NAMES.has(name)) durations.set(name, entry.duration_ds ?? 1);
    }
  }
  const known = new Set(durations.keys());
  for (const name of enumerateUnitTestTypes()) {
    if (!SWEEP_TEST_NAMES.has(name)) known.add(name);
  }
  if (selection) for (const name of [...known]) if (!selection.has(name)) known.delete(name);
  const DEFAULT_WEIGHT_DS = 5; // ~0.5s: most non-sweep tests are quick
  const sorted = [...known].sort(
    (a, b) => (durations.get(b) ?? DEFAULT_WEIGHT_DS) - (durations.get(a) ?? DEFAULT_WEIGHT_DS),
  );
  for (const name of sorted) {
    let lightest = 0;
    for (let i = 1; i < shardCount; i++) if (loads[i] < loads[lightest]) lightest = i;
    shards[lightest].push(name);
    loads[lightest] += durations.get(name) ?? DEFAULT_WEIGHT_DS;
  }
  return shards;
}

type ShardRun = WorldRun & { index: number };

/** Boots one shard's world: its own log directory, results file and process
 * sampler (data/logs/shardN, data/unit_tests-shardN.json,
 * data/bench/process-shardN.json) so N concurrent worlds in the same
 * worktree never share a path, and its own machine-wide dd-slot (see
 * lib/dd_slot.ts) so shards throttle against the same budget as every other
 * DreamDaemon on this machine. The slot is released the moment this
 * shard's daemon exits, not when every shard finishes. */
async function runShardWorld(
  dmbFile: string,
  dmVersion: string | null,
  shardIndex: number,
  shardCount: number,
  testsFile: string,
  priority: boolean,
  selectFile: string | null,
): Promise<ShardRun> {
  const tag = `shard${shardIndex}`;
  Juke.rm(`data/logs/${tag}`, { recursive: true });
  const resultsFile = `data/unit_tests-${tag}.json`;
  Juke.rm(resultsFile);
  fs.mkdirSync('data/bench', { recursive: true });
  const sampler = new ProcessSampler(`data/bench/process-${tag}.json`);
  const slot = await acquireDdSlot(priority);
  const params = new URLSearchParams({
    'log-directory': tag,
    'unit-tests-file': resultsFile,
    'shard-index': String(shardIndex),
    'shard-count': String(shardCount),
    'shard-tests': testsFile,
    ...(selectFile ? { 'test-select': selectFile } : {}),
  }).toString();
  // Each shard does roughly 1/shardCount of the suite's work (sweeps
  // self-divide via sweep_types(), non-sweep tests are bin-packed), so its
  // watchdog backstop scales down with shard count too -- sqrt rather than
  // linear, since per-world boot/settle overhead and any single still-heavy
  // sweep slice don't shrink that fast. Floored at 12 minutes;
  // DQ_DD_WATCHDOG_MINUTES (read in lib/byond.ts) overrides this entirely.
  const shardWatchdogMs = Math.max(Math.round((45 / Math.sqrt(shardCount)) * 60 * 1000), 12 * 60 * 1000);
  const started = Date.now();
  let killedByWatchdog = false;
  try {
    const result = await DreamDaemon(
      {
        dmbFile,
        namedDmVersion: dmVersion,
        watchdogFile: resultsFile,
        onSpawn: (pid) => sampler.start(pid),
        watchdogTimeoutMs: shardWatchdogMs,
      },
      '-close',
      ddSecurityFlag(),
      '-verbose',
      '-params',
      params,
    );
    killedByWatchdog = !!result.killedByWatchdog;
  } catch {
    // DreamDaemon exits non-zero even on clean runs; the files below decide.
  } finally {
    slot.release();
  }
  const processSummary = sampler.stop();
  let cleanText: string | null = null;
  try {
    cleanText = fs.readFileSync(`data/logs/${tag}/clean_run.lk`, 'utf-8');
  } catch {
    // not clean
  }
  let results: Record<string, UnitTestEntry> | null = null;
  try {
    results = JSON.parse(fs.readFileSync(resultsFile, 'utf-8'));
  } catch {
    // the world died before finishing
  }
  return {
    index: shardIndex,
    clean: cleanText !== null,
    cleanText,
    results,
    durationSeconds: (Date.now() - started) / 1000,
    process: processSummary,
    samples: sampler.samples,
    killedByWatchdog,
  };
}

function statusPriority(status: number): number {
  if (status === 1) return 2; // failed: always wins
  if (status === 0) return 0; // passed: loses to anything else recorded
  return 1; // skipped
}

/** Merges every shard's results into one summary. A sweep test's entries
 * (one per shard, each its own slice) sum durations/runtimes/tick counts and
 * take the worst status; a non-sweep test should only ever appear in the one
 * shard it was assigned to, but is merged the same defensive way. */
function mergeShardResults(runs: ShardRun[]): {
  results: Record<string, UnitTestEntry>;
  clean: boolean;
  totalCpuSeconds: number;
} {
  const merged: Record<string, UnitTestEntry> = {};
  let clean = true;
  let totalCpuSeconds = 0;
  for (const run of runs) {
    if (!run.clean) clean = false;
    totalCpuSeconds += run.process?.cpu_seconds ?? 0;
    if (!run.results) continue;
    for (const [name, entry] of Object.entries(run.results)) {
      const existing = merged[name];
      if (!existing) {
        merged[name] = { ...entry };
        continue;
      }
      const existingWins = statusPriority(existing.status) >= statusPriority(entry.status);
      merged[name] = {
        status: existingWins ? existing.status : entry.status,
        message: existingWins ? existing.message : entry.message,
        name,
        duration_ds: (existing.duration_ds ?? 0) + (entry.duration_ds ?? 0),
        runtimes: (existing.runtimes ?? 0) + (entry.runtimes ?? 0),
        ticks:
          existing.ticks && entry.ticks
            ? {
                samples: existing.ticks.samples + entry.ticks.samples,
                overruns: existing.ticks.overruns + entry.ticks.overruns,
                max: Math.max(existing.ticks.max, entry.ticks.max),
              }
            : (entry.ticks ?? existing.ticks),
      };
    }
  }
  return { results: merged, clean, totalCpuSeconds };
}

/** The `--shards=N` path for DmTestTarget: compiles once, boots N worlds in
 * parallel (each racing the same dd-slot budget as everything else on the
 * machine), and merges their results into one data/test-runs/ record. */
async function runSharded(shardCount: number, get: any): Promise<void> {
  reportFocus();
  await compileDerived(`${DME_NAME}.test.dme`, get, TEST_DEFINES);
  const priority = process.env.DQ_DD_PRIORITY === '1';
  fs.mkdirSync(SHARD_DIR, { recursive: true });
  const selection = resolveTestSelection(get);
  const selectionSet = selection ? new Set(selection) : null;
  let selectFile: string | null = null;
  if (selection) {
    selectFile = `${SHARD_DIR}/select.txt`;
    fs.writeFileSync(selectFile, selection.length ? `${selection.join('\n')}\n` : '');
  }
  const assignment = assignTestShards(shardCount, selectionSet);
  const testFiles: string[] = [];
  for (let i = 0; i < shardCount; i++) {
    const file = `${SHARD_DIR}/shard-${i}-of-${shardCount}.txt`;
    fs.writeFileSync(file, assignment[i].length ? `${assignment[i].join('\n')}\n` : '');
    testFiles.push(file);
  }
  Juke.logger.info(
    `dm-test --shards=${shardCount}: `
      + `${assignment.map((a, i) => `shard ${i}: ${a.length} test(s)`).join(', ')}, `
      + `plus every sweep test in each shard${selection ? ' that matches the selection' : ''}.`,
  );
  const shardWatchdogMinutes = Math.max(45 / Math.sqrt(shardCount), 12);
  const started = Date.now();
  const runs = await Promise.all(
    Array.from({ length: shardCount }, (_, i) =>
      runShardWorld(`${DME_NAME}.test.dmb`, get(DmVersionParameter), i, shardCount, testFiles[i], priority, selectFile)),
  );
  const wallSeconds = (Date.now() - started) / 1000;
  for (const run of runs) {
    if (run.killedByWatchdog) {
      Juke.logger.error(
        `Shard ${run.index}: the DreamDaemon watchdog force-killed this world for running past its `
          + `${Math.round(shardWatchdogMinutes)}min hard timeout (DQ_DD_WATCHDOG_MINUTES to raise it). `
          + `${run.results ? 'Partial' : 'No'} results were captured.`,
      );
    }
    if (!run.clean) {
      Juke.logger.error(`Shard ${run.index} was not clean:`);
      for (const logFile of [`data/logs/shard${run.index}/tests.log`, `data/logs/shard${run.index}/runtime.log`]) {
        if (!fs.existsSync(logFile)) continue;
        const lines = fs.readFileSync(logFile, 'utf-8').trim().split(/\r?\n/);
        console.error(lines.slice(-40).join('\n'));
      }
    }
  }
  const { results, clean, totalCpuSeconds } = mergeShardResults(runs);
  const record = testRunRecord(
    runIdentity(get(LabelParameter)),
    get(LabelParameter),
    [...TEST_DEFINES, ...get(DefineParameter)],
    clean,
    wallSeconds,
    results,
  );
  writeJson(`${TEST_RUNS_DIR}/${record.id}.json`, record);
  Juke.logger.info(
    `Unit-test summary (${shardCount} shards): ${record.counts.passed} passed, ${record.counts.failed} failed, `
      + `${record.counts.skipped} skipped in ${Math.round(wallSeconds)}s wall / ~${Math.round(totalCpuSeconds)}s `
      + `summed CPU (saved ${TEST_RUNS_DIR}/${record.id}.json).`,
  );
  console.log(testHotspots(results, 20));
  for (const name of record.failed) {
    Juke.logger.error(`FAILED ${name}: ${results[name].message ?? ''}`);
  }
  await removeDerivedArtifacts(`${DME_NAME}.test.dme`);
  if (!clean) {
    Juke.logger.error('Sharded test run was not clean, exiting');
    throw new Juke.ExitCode(1);
  }
}

export const DmTestTarget = new Juke.Target({
  parameters: [
    DefineParameter,
    DmVersionParameter,
    WarningParameter,
    NoWarningParameter,
    LabelParameter,
    ShardsParameter,
    DomainsParameter,
    TierParameter,
    AffectedParameter,
  ],
  dependsOn: ({ get }) => [
    get(DefineParameter).includes('ALL_MAPS') && DmMapsIncludeTarget,
    IconRepackTarget, // tests boot the world, which uses the .rsc
    ValidateDmeTarget, // catch missing includes before compiling
    VerdigrisTarget, // tests boot the world, which loads the FFI lib
    MapBoundsTarget, // tests boot the world, which reads template bounds
  ],
  executes: async ({ get }) => {
    const shardCount = Math.max(get(ShardsParameter) ?? 1, 1);
    if (shardCount > 1) {
      await runSharded(shardCount, get);
      return;
    }
    reportFocus();
    await compileDerived(`${DME_NAME}.test.dme`, get, TEST_DEFINES);
    const selection = resolveTestSelection(get);
    let worldParams: Record<string, string> = {};
    if (selection) {
      fs.mkdirSync(SHARD_DIR, { recursive: true });
      const selectFile = `${SHARD_DIR}/select.txt`;
      fs.writeFileSync(selectFile, selection.length ? `${selection.join('\n')}\n` : '');
      worldParams = { 'test-select': selectFile };
    }
    const run = await runTestWorld(`${DME_NAME}.test.dmb`, get(DmVersionParameter), worldParams, false);
    if (!run.clean) printLogTails();
    recordTestRun(run, get(LabelParameter), get(DefineParameter));
    // Keep deepquarry.test.dmb/.rsc (only drop the derived .dme text) so an
    // unchanged rerun -- a flake recheck, a focused rerun while iterating --
    // can reuse them via compileDerived()'s content-hash cache instead of
    // recompiling. removeDerivedArtifacts() in compileDerived()'s catch
    // already cleans up fully on a failed compile.
    await removeDerivedArtifacts(`${DME_NAME}.test.dme`);
    if (!run.clean) {
      Juke.logger.error('Test run was not clean, exiting');
      throw new Juke.ExitCode(1);
    }
    console.log(run.cleanText);
  },
});

/**
 * Runs the suite several times on one build and sorts failures into
 * consistent and flaky. `--runs` defaults to 3.
 */
export const TestRepeatTarget = new Juke.Target({
  parameters: [DefineParameter, DmVersionParameter, WarningParameter, NoWarningParameter, RunsParameter],
  dependsOn: [IconRepackTarget, ValidateDmeTarget, VerdigrisTarget, MapBoundsTarget],
  executes: async ({ get }) => {
    const runs = Math.max(get(RunsParameter) ?? 3, 1);
    reportFocus();
    await compileDerived(`${DME_NAME}.test.dme`, get, TEST_DEFINES);
    const outcomes: Record<string, number[]> = {};
    for (let i = 1; i <= runs; i++) {
      Juke.logger.info(`Test repeat ${i}/${runs}`);
      const run = await runTestWorld(`${DME_NAME}.test.dmb`, get(DmVersionParameter), {}, false);
      recordTestRun(run, `repeat${i}of${runs}`, get(DefineParameter));
      for (const [name, result] of Object.entries(run.results ?? {})) {
        (outcomes[name] ??= []).push(result.status);
      }
    }
    // See the matching comment in DmTestTarget: keep the .dmb/.rsc for reuse.
    await removeDerivedArtifacts(`${DME_NAME}.test.dme`);
    const consistent = Object.entries(outcomes).filter(([, s]) => s.length === runs && s.every((v) => v === 1));
    const flaky = Object.entries(outcomes).filter(([, s]) => s.includes(1) && !s.every((v) => v === 1));
    Juke.logger.info(`Across ${runs} runs: ${consistent.length} consistent failure(s), ${flaky.length} flaky test(s).`);
    for (const [name] of consistent) console.log(`  always fails  ${name}`);
    for (const [name, s] of flaky) console.log(`  flaky ${s.filter((v) => v === 1).length}/${s.length}   ${name}`);
    if (consistent.length || flaky.length) throw new Juke.ExitCode(1);
  },
});

/** Prints new, fixed and shared failures between two stored test runs. */
function compareTestRuns(base: TestRun, head: TestRun): { newFailures: string[] } {
  const baseFailed = new Set(base.failed);
  const headFailed = new Set(head.failed);
  const newFailures = head.failed.filter((t) => !baseFailed.has(t));
  const fixed = base.failed.filter((t) => !headFailed.has(t));
  const shared = head.failed.filter((t) => baseFailed.has(t));
  const missing = Object.keys(base.tests).filter((t) => !(t in head.tests));
  const added = Object.keys(head.tests).filter((t) => !(t in base.tests));
  console.log(`Base ${base.id} (${base.counts.failed} failed) -> head ${head.id} (${head.counts.failed} failed)`);
  const section = (title: string, items: string[]) => {
    if (!items.length) return;
    console.log(`${title} (${items.length}):`);
    for (const item of items) console.log(`  ${item}`);
  };
  section('New failures', newFailures);
  section('Fixed', fixed);
  section('Failing in both', shared);
  section('Tests only in base', missing);
  section('Tests only in head', added);
  return { newFailures };
}

export const TestCompareTarget = new Juke.Target({
  parameters: [BaseParameter, HeadParameter],
  executes: async ({ get }) => {
    const base = readJson<TestRun>(resolveRun(TEST_RUNS_DIR, get(BaseParameter) || 'previous'));
    const head = readJson<TestRun>(resolveRun(TEST_RUNS_DIR, get(HeadParameter) || 'latest'));
    if (compareTestRuns(base, head).newFailures.length) throw new Juke.ExitCode(1);
  },
});

/**
 * Runs the suite on another commit (default HEAD, i.e. without your
 * uncommitted changes) in a reusable worktree, then compares it with the
 * latest local test run. Answers "is this failure mine or pre-existing?".
 */
export const TestBaselineTarget = new Juke.Target({
  parameters: [RefParameter, DefineParameter],
  executes: async ({ get }) => {
    const ref = get(RefParameter) || 'HEAD';
    const commit = spawnSync('git', ['rev-parse', '--short=10', ref], { encoding: 'utf-8' }).stdout.trim();
    if (!commit) {
      Juke.logger.error(`Unknown git ref '${ref}'.`);
      throw new Juke.ExitCode(1);
    }
    const root = process.cwd();
    const worktree = path.join(os.tmpdir(), `dq-baseline-${commit}`);
    if (!fs.existsSync(worktree)) {
      Juke.logger.info(`Creating baseline worktree for ${ref} (${commit}) at ${worktree}`);
      await Juke.exec('git', ['worktree', 'add', '--detach', worktree, commit]);
    } else {
      Juke.logger.info(`Reusing baseline worktree ${worktree}`);
    }
    // Seed the generated icons so the repack only redoes what differs.
    if (fs.existsSync('icons/gen') && !fs.existsSync(path.join(worktree, 'icons/gen'))) {
      fs.cpSync('icons/gen', path.join(worktree, 'icons/gen'), { recursive: true });
    }
    const script = process.platform === 'win32' ? 'tools\\build\\build.bat' : 'tools/build/build.sh';
    const defines = get(DefineParameter).flatMap((d) => ['-D', d]);
    try {
      await Juke.exec(script, ['dm-test', '--label', `baseline-${commit}`, ...defines], {
        cwd: worktree,
        shell: process.platform === 'win32',
        env: { ...process.env, CARGO_TARGET_DIR: path.join(root, 'verdigris', 'target') },
      });
    } catch {
      // failures are expected; the record decides
    }
    const baselineRuns = listRuns(path.join(worktree, TEST_RUNS_DIR));
    if (!baselineRuns.length) {
      Juke.logger.error('The baseline run produced no results (compile or boot failure). See the output above.');
      throw new Juke.ExitCode(1);
    }
    const baselineFile = baselineRuns[baselineRuns.length - 1];
    const copied = path.join(TEST_RUNS_DIR, path.basename(baselineFile));
    fs.mkdirSync(TEST_RUNS_DIR, { recursive: true });
    fs.copyFileSync(baselineFile, copied);
    const local = listRuns(TEST_RUNS_DIR).filter((f) => !path.basename(f).includes('baseline-'));
    if (!local.length) {
      Juke.logger.warn('No local test run to compare against; run dm-test first. Baseline saved.');
      return;
    }
    compareTestRuns(readJson<TestRun>(copied), readJson<TestRun>(local[local.length - 1]));
    Juke.logger.info(`Remove the worktree when done: git worktree remove --force ${worktree}`);
  },
});

/**
 * Boots a -DBENCHMARK build and runs scenarios from code/modules/benchmarks/,
 * sampling DreamDaemon's memory and CPU from outside. Each invocation is stored
 * in data/bench/runs/ and compared with the previous run on the same map.
 */
export const BenchTarget = new Juke.Target({
  parameters: [
    DefineParameter, DmVersionParameter, WarningParameter, NoWarningParameter,
    ScenarioParameter, RunsParameter, WarmupParameter, ArgParameter, ProfileParameter, LabelParameter,
  ],
  dependsOn: [IconRepackTarget, ValidateDmeTarget, VerdigrisTarget, MapBoundsTarget],
  executes: async ({ get }) => {
    const scenarios = get(ScenarioParameter).flatMap((s) => s.split(','));
    const runs = Math.max(get(RunsParameter) ?? 1, 1);
    const warmup = Math.max(get(WarmupParameter) ?? (runs > 1 ? 1 : 0), 0);
    const worldParams: Record<string, string> = { bench: scenarios.length ? scenarios.join(',') : 'default' };
    if (get(ProfileParameter)) worldParams.bench_profile = '1';
    for (const arg of get(ArgParameter)) {
      const [key, ...rest] = arg.split('=');
      worldParams[`bench_${key}`] = rest.join('=');
    }
    await compileDerived(`${DME_NAME}.bench.dme`, get, [...TEST_DEFINES, 'BENCHMARK']);
    const identity = runIdentity(get(LabelParameter));
    const iterations: BenchIteration[] = [];
    const failures: string[] = [];
    for (let i = 1; i <= warmup + runs; i++) {
      const isWarmup = i <= warmup;
      Juke.logger.info(`Benchmark iteration ${i}/${warmup + runs}${isWarmup ? ' (warm-up, not counted)' : ''}`);
      const run = await runTestWorld(`${DME_NAME}.bench.dmb`, get(DmVersionParameter), worldParams, true);
      let world: WorldBenchDocument;
      try {
        world = readJson<WorldBenchDocument>('data/bench/scenarios.json');
      } catch {
        printLogTails();
        failures.push(`iteration ${i}: the world wrote no benchmark results`);
        continue;
      }
      for (const scenario of Object.values(world.scenarios)) {
        if (scenario.status !== 'passed') failures.push(`iteration ${i}: ${scenario.id} ${scenario.status}: ${scenario.error ?? ''}`);
      }
      const profiles: string[] = [];
      if (fs.existsSync('data/logs/ci/profiler')) {
        const dest = `data/bench/profiles/${identity.id}/iteration${i}`;
        fs.mkdirSync(dest, { recursive: true });
        for (const file of fs.readdirSync('data/logs/ci/profiler')) {
          fs.copyFileSync(`data/logs/ci/profiler/${file}`, `${dest}/${file}`);
          profiles.push(`${dest}/${file}`);
        }
      }
      iterations.push({
        ...world,
        iteration: i,
        warmup: isWarmup,
        process: run.process as ProcessSummary,
        process_samples: run.samples,
        profiles,
      });
    }
    await removeDerivedArtifacts('*.bench.*');
    const record: BenchRun = {
      ...identity,
      kind: 'bench',
      label: get(LabelParameter),
      map: iterations[0]?.map ?? 'unknown',
      defines: get(DefineParameter),
      scenarios_requested: scenarios,
      args: get(ArgParameter),
      iterations,
      summary: summarize(iterations),
      failures,
    };
    const file = `${BENCH_RUNS_DIR}/${record.id}.json`;
    writeJson(file, record);
    for (const [scenario, metrics] of Object.entries(record.summary)) {
      console.log(`\n${scenario}`);
      for (const [name, stats] of Object.entries(metrics)) {
        const spread = stats.n > 1 ? ` ±${formatNumber(stats.stdev)}` : '';
        console.log(`  ${name.padEnd(40)} ${formatNumber(stats.median).padStart(10)} ${stats.unit}${spread}`);
      }
    }
    Juke.logger.info(`Saved ${file}`);
    const sameMap = listRuns(BENCH_RUNS_DIR)
      .map((f) => readJson<BenchRun>(f))
      .filter((r) => r.map === record.map && r.id !== record.id);
    if (sameMap.length) {
      const previous = sameMap[sameMap.length - 1];
      console.log(`\nCompared with ${previous.id}:`);
      console.log(formatComparison(compareRuns(previous, record, 5), true));
    }
    renderReport('data/bench/report.html');
    Juke.logger.info('Report: data/bench/report.html');
    if (failures.length) {
      for (const failure of failures) Juke.logger.error(failure);
      throw new Juke.ExitCode(1);
    }
  },
});

export const BenchCompareTarget = new Juke.Target({
  parameters: [BaseParameter, HeadParameter, ThresholdParameter, FailOnRegressionParameter, AllParameter],
  executes: async ({ get }) => {
    const baseFile = resolveRun(BENCH_RUNS_DIR, get(BaseParameter) || 'previous');
    const headFile = resolveRun(BENCH_RUNS_DIR, get(HeadParameter) || 'latest');
    const base = readJson<BenchRun>(baseFile);
    const head = readJson<BenchRun>(headFile);
    if (base.map !== head.map) Juke.logger.warn(`Comparing different maps: ${base.map} vs ${head.map}`);
    const rows = compareRuns(base, head, get(ThresholdParameter) ?? 5);
    console.log(`Base ${base.id}\nHead ${head.id}\n`);
    console.log(formatComparison(rows, !get(AllParameter)));
    const regressions = rows.filter((r) => r.verdict === 'regression');
    const improvements = rows.filter((r) => r.verdict === 'improvement');
    Juke.logger.info(`${regressions.length} regression(s), ${improvements.length} improvement(s), ${rows.length} metrics compared.`);
    if (get(FailOnRegressionParameter) && regressions.length) throw new Juke.ExitCode(1);
  },
});

export const BenchReportTarget = new Juke.Target({
  executes: async () => {
    const { runs, tests } = renderReport('data/bench/report.html');
    Juke.logger.info(`Wrote data/bench/report.html (${runs} benchmark runs, ${tests} test runs).`);
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
    VerdigrisTarget, // DQAdd — autowiki boots the world, which loads the FFI lib
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
      ddSecurityFlag(),
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

// Entry bundles that must always exist after a successful tgui build.
const TGUI_ENTRY_BUNDLES = [
  'tgui/public/tgui.bundle.js',
  'tgui/public/tgui.bundle.css',
  'tgui/public/tgui-panel.bundle.js',
  'tgui/public/tgui-panel.bundle.css',
  'tgui/public/tgui-say.bundle.js',
  'tgui/public/tgui-say.bundle.css',
];
const TGUI_CHUNK_MANIFEST = 'tgui/public/tgui-chunk-manifest.json';
const TGUI_WINDOW_MANIFEST = 'tgui/public/tgui-window-manifest.json';

// True only if the tgui bundle in public/ is COMPLETE: the entry bundles exist and
// are non-empty, the chunk manifest parses, and every interface chunk it references
// is present and non-empty. The individual *.chunk.* files aren't tracked as Juke
// outputs (they're content-hashed and numerous), so without this check an interrupted
// or corrupt rspack emit — entry bundles written but some interface chunks missing —
// passes the mtime dirty-check forever and silently serves blank/grey UI windows
// (e.g. the lobby) until public/ is wiped by hand.
const tguiBundleComplete = (): boolean => {
  const nonEmpty = (p: string): boolean => {
    try {
      return fs.statSync(p).size > 0;
    } catch {
      return false;
    }
  };
  if (!TGUI_ENTRY_BUNDLES.every(nonEmpty)) {
    return false;
  }
  if (!nonEmpty(TGUI_CHUNK_MANIFEST)) {
    return false;
  }
  if (!nonEmpty(TGUI_WINDOW_MANIFEST)) {
    return false;
  }
  let manifest: Record<string, string[]>;
  try {
    manifest = JSON.parse(fs.readFileSync(TGUI_CHUNK_MANIFEST, 'utf8'));
    const geometry = JSON.parse(
      fs.readFileSync(TGUI_WINDOW_MANIFEST, 'utf8'),
    ) as Record<string, { width: number; height: number; exact: boolean }>;
    if (!Object.keys(geometry).length) return false;
    for (const interfaceName of Object.keys(manifest)) {
      const entry = geometry[interfaceName];
      if (!entry || entry.width <= 0 || entry.height <= 0) return false;
    }
  } catch {
    return false;
  }
  for (const files of Object.values(manifest)) {
    for (const file of files) {
      if (!nonEmpty(`tgui/public/${file}`)) {
        return false;
      }
    }
  }
  return true;
};

export const TguiTarget = new Juke.Target({
  dependsOn: [BunTarget, BiomeInstallTarget],
  inputs: [
    'tgui/rspack.config.ts',
    'tgui/**/package.json',
    'tgui/packages/**/*.+(js|cjs|ts|tsx|jsx|scss|svg)',
  ],
  outputs: [
    'tgui/public/tgui.bundle.css',
    'tgui/public/tgui.bundle.js',
    'tgui/public/tgui-panel.bundle.css',
    'tgui/public/tgui-panel.bundle.js',
    'tgui/public/tgui-say.bundle.css',
    'tgui/public/tgui-say.bundle.js',
    // Code-split interface chunks are emitted alongside the entry bundles; the
    // manifest maps interface name -> chunk file (consumed by SStgui). Tracking the
    // manifest as an output makes Juke rebuild if it's missing (e.g. a public/ wipe)
    // and keeps it in sync with rspack.config.ts changes. The individual *.chunk.*
    // files are content-id'd and numerous, so they aren't listed literally — instead
    // tguiBundleComplete() validates them (see onlyWhen / executes below).
    'tgui/public/tgui-chunk-manifest.json',
    'tgui/public/tgui-window-manifest.json',
  ],
  // Runs before the mtime dirty-check. If the existing bundle is incomplete (a chunk
  // the manifest references is missing/empty), drop the tracked entry bundles so the
  // mtime check treats the outputs as missing and forces a fresh rebuild — otherwise
  // a half-written bundle is skipped indefinitely and serves broken UI.
  onlyWhen: () => {
    if (!tguiBundleComplete()) {
      for (const f of TGUI_ENTRY_BUNDLES) {
        try {
          fs.rmSync(f);
        } catch {
          /* already gone */
        }
      }
    }
    return true;
  },
  executes: async () => {
    await bun('tgui:build');
    // Fail loudly instead of silently shipping a broken UI: if rspack returned 0 but
    // the emit is incomplete (a flaky/interrupted build), throw so the build is red
    // and the partial bundle isn't accepted.
    if (!tguiBundleComplete()) {
      throw new Error(
        'tgui build finished but the bundle is incomplete (missing/empty interface '
          + 'chunks). Re-run the build; if it persists, delete '
          + 'tgui/public/*.{bundle,chunk}.* and rebuild.',
      );
    }
  },
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
    if (!findDreamChecker()) {
      Juke.logger.info(
        'dreamchecker not found on PATH, DREAMCHECKER_EXE, or ~/SpacemanDMM — skipping DM lint (install via tools/ci/install_spaceman_dmm.sh)',
      );
      return false;
    }
    return true;
  },
  executes: async () => {
    const dreamChecker = findDreamChecker();
    if (!dreamChecker) {
      throw new Error('DreamChecker disappeared after dependency detection.');
    }
    // DreamChecker 1.11 auto-selects a root-level DME when multiple manifests
    // are present, even though SpacemanDMM.toml names deepquarry.dme. Local
    // profiling creates audit*.dme copies concurrently, which previously made
    // release builds lint a UNIT_TESTS manifest instead of production code.
    const stashDirectory = 'data/.dreamchecker-dme-stash';
    fs.mkdirSync(stashDirectory, { recursive: true });
    const stashed = fs.readdirSync('.')
      .filter((name) => name.endsWith('.dme') && name !== `${DME_NAME}.dme`)
      .map((name) => {
        const destination = `${stashDirectory}/${name}`;
        fs.renameSync(name, destination);
        return { destination, name };
      });
    try {
      await Juke.exec(dreamChecker, []);
    } finally {
      for (const { destination, name } of stashed) {
        if (fs.existsSync(destination) && !fs.existsSync(name)) {
          fs.renameSync(destination, name);
        }
      }
    }
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
    const webroot = spawn(
      process.platform === 'win32' ? 'python' : 'python3',
      ['tools/localhost-asset-webroot-server.py'],
      { stdio: 'ignore', windowsHide: true },
    );
    webroot.on('error', () => {
      Juke.logger.warn(
        'Could not start the local asset webroot; use the configured external webroot.',
      );
    });
    try {
      await DreamDaemon(
        options,
        port,
        ddSecurityFlag('trusted'),
        '-invisible',
        '-params',
        'config-directory=config/example',
      );
    } finally {
      webroot.kill();
    }
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
