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
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import Juke from './juke/index.js';
import { bun, bunRoot } from './lib/bun';
import { acquireDdSlot, countFreeDdSlots } from './lib/dd_slot';
import { generateVerdigrisBindings } from './lib/verdigris_bindings';
import {
  BALANCE_RESULTS_FILE,
  BALANCE_RUNS_DIR,
  type BalanceRun,
  type BalanceWorldDocument,
  balanceFailures,
  compareBalance,
  formatBalanceChanges,
  readBalanceResults,
} from './lib/balance';
import {
  acquireBenchExclusiveLock,
  BENCH_RUNS_DIR,
  benchRunsDir,
  benchStoreDir,
  type BenchIteration,
  type BenchRun,
  compareRuns,
  findBaselineRun,
  formatComparison,
  formatNumber,
  type LoadContext,
  listRuns,
  LoadSampler,
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
  waitForDreamDaemonsToDrain,
  type WorldBenchDocument,
  writeJson,
} from './lib/bench';
import { renderReport } from './lib/bench_report';
import { checkVerdigrisAbi, DreamDaemon, DreamMaker, NamedVersionFile } from './lib/byond';
import { prependDefines } from './lib/tgs';
import { MAP_BOUNDS_FILE, writeMapBounds } from './lib/map_bounds';
import {
  checkVerdigrisProvenance,
  installVerdigrisLibrary,
  verdigrisInputHash,
} from './lib/verdigris_provenance';
import {
  dropVerdigris,
  restoreVerdigris,
  storeVerdigris,
  verdigrisCacheDir,
  verdigrisCacheKey,
} from './lib/verdigris_cache';

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

// Worktree guard. Many agents build in parallel git worktrees with
// byte-identical build.ts; Bun's shared runtime transpiler cache has been
// observed resolving one worktree's invocation to another checkout, silently
// overwriting the wrong deepquarry.dmb. The entry scripts disable that cache
// and export DQ_BUILD_ROOT (derived by the shell, not by Bun); refuse to run
// unless the root we chdir'd into is the invoking worktree's toplevel.
{
  const real = (p: string) => fs.realpathSync.native(path.resolve(p)).toLowerCase();
  const scriptRoot = path.resolve(path.dirname(process.argv[1] ?? '.'), '../..');
  const expected = process.env.DQ_BUILD_ROOT || scriptRoot;
  const top = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: expected, encoding: 'utf-8' });
  const toplevel = top.status === 0 ? top.stdout.trim() : expected;
  const roots = { cwd: process.cwd(), argv: scriptRoot, DQ_BUILD_ROOT: expected, git: toplevel };
  const distinct = new Set(Object.values(roots).map(real));
  if (distinct.size !== 1) {
    console.error('build.ts: repo root mismatch, refusing to build the wrong checkout:');
    for (const [k, v] of Object.entries(roots)) console.error(`  ${k}: ${v}`);
    console.error('  (stale Bun transpiler cache? run via tools/build/build.sh, or set BUN_RUNTIME_TRANSPILER_CACHE_PATH=0)');
    process.exit(1);
  }
}

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
    ], {
      // The repack watches this pid and exits (with its worker pool) when the build
      // dies; Windows does not kill child processes with their parent.
      env: { ...process.env, DQ_BUILD_PID: String(process.pid) },
    });
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
  // Generates code/engine/_generated first (GenTarget, defined below: hence the function form).
  dependsOn: () => [GenTarget],
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
const VERDIGRIS_PROVENANCE = `${VERDIGRIS_LIB}.provenance.json`;
// Provenance checking (lib/verdigris_provenance.ts) proves a library was built
// from this checkout's Rust inputs. It needs the Rust build to embed
// VERDIGRIS_SOURCE_HASH from DQ_VERDIGRIS_INPUT_HASH, which the crates do not do
// yet, so it is opt-in: DQ_VERDIGRIS_PROVENANCE=1. Off, the target behaves as before.
const VERDIGRIS_PROVENANCE_ENFORCED = process.env.DQ_VERDIGRIS_PROVENANCE === '1';
const verdigrisProvenanceMismatch = (): string | null =>
  VERDIGRIS_PROVENANCE_ENFORCED
    ? checkVerdigrisProvenance(process.cwd(), VERDIGRIS_LIB, VERDIGRIS_RUST_TARGET, process.env.RUSTFLAGS || '')
    : null;

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

// The bindings check reads every Rust source and every DM file (15+ s on Windows). It is skipped when nothing it
// reads has changed since it last passed here: the Rust sources and the generated files by content, the DM tree by
// its file list (the DM side only checks that the types a component names exist; editing inside a file that removes
// such a type is caught by CI, which always runs the full check, and by the next Rust or file-list change).
// data/verdigris-bindings-check.json holds the key; DQ_FULL_CHECKS=1 forces the full check.
const verdigrisBindingsCheckKey = (): string => {
  const hash = createHash('sha256').update('vg-bindings-check-v1|');
  const rs: string[] = [];
  const walk = (dir: string, keep: (name: string) => boolean, out: string[]) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === 'target' || entry.name.startsWith('target-') || entry.name === 'node_modules') continue;
      const full = `${dir}/${entry.name}`;
      if (entry.isDirectory()) walk(full, keep, out);
      else if (keep(entry.name)) out.push(full);
    }
  };
  walk('verdigris', (n) => n.endsWith('.rs') || n === 'Cargo.toml', rs);
  walk('code/__defines/verdigris', (n) => n.endsWith('.dm'), rs);
  for (const file of rs.sort()) {
    hash.update(file);
    hash.update(fs.readFileSync(file));
  }
  const dm: string[] = [];
  walk('code', (n) => n.endsWith('.dm'), dm);
  hash.update(dm.sort().join('\n'));
  return hash.digest('hex');
};
const VERDIGRIS_BINDINGS_CHECK_RECORD = 'data/verdigris-bindings-check.json';

export const VerdigrisBindingsCheckTarget = new Juke.Target({
  executes: () => {
    const full = !!process.env.CI || process.env.DQ_FULL_CHECKS === '1';
    const key = full ? null : verdigrisBindingsCheckKey();
    if (key) {
      try {
        if (JSON.parse(fs.readFileSync(VERDIGRIS_BINDINGS_CHECK_RECORD, 'utf-8')).key === key) {
          Juke.logger.info('verdigris bindings: inputs unchanged since the last passing check; skipped');
          return;
        }
      } catch {
        // no record yet
      }
    }
    const stale = generateVerdigrisBindings(process.cwd(), true);
    if (key && !stale.length) {
      fs.mkdirSync('data', { recursive: true });
      fs.writeFileSync(VERDIGRIS_BINDINGS_CHECK_RECORD, JSON.stringify({ key, checkedAt: new Date().toISOString() }));
    }
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

// Shared content-addressed cache of built libraries (lib/verdigris_cache.ts), so a
// fresh worktree copies the DLL instead of compiling the Rust workspace.
const verdigrisAbi = (): string | undefined => {
  try {
    return /#define VERDIGRIS_ABI "([0-9a-f]+)"/.exec(
      fs.readFileSync('code/__defines/verdigris/_bindings.dm', 'utf-8'),
    )?.[1];
  } catch {
    return undefined;
  }
};
let verdigrisPendingStore: { cache: string; key: string; commit: string } | null = null;
const verdigrisCacheHit = (): boolean => {
  verdigrisPendingStore = null;
  const cache = verdigrisCacheDir();
  if (!cache) return false;
  const k = verdigrisCacheKey(
    process.cwd(),
    VERDIGRIS_RUST_TARGET,
    process.env.RUSTFLAGS || '',
    VERDIGRIS_PROVENANCE_ENFORCED ? 'provenance' : '',
  );
  if ('bypass' in k) {
    Juke.logger.info(`verdigris cache: bypassed (${k.bypass})`);
    return false;
  }
  const sidecars = VERDIGRIS_PROVENANCE_ENFORCED ? [VERDIGRIS_PROVENANCE] : [];
  if (restoreVerdigris(cache, k.key, VERDIGRIS_LIB, sidecars)) {
    const abi = verdigrisAbi();
    const abiOk = !abi || fs.readFileSync(VERDIGRIS_LIB).includes(Buffer.from(abi, 'latin1'));
    if (abiOk && !verdigrisProvenanceMismatch()) {
      Juke.logger.info(`verdigris cache: hit ${k.key} (${cache})`);
      return true;
    }
    Juke.logger.warn(`verdigris cache: entry ${k.key} fails the ABI/provenance check; dropping it and rebuilding`);
    dropVerdigris(cache, k.key);
    fs.rmSync(VERDIGRIS_LIB, { force: true });
  } else {
    Juke.logger.info(`verdigris cache: miss ${k.key}; building and storing`);
  }
  verdigrisPendingStore = { cache, key: k.key, commit: k.commit };
  return false;
};
const storeVerdigrisBuild = (built: string): void => {
  const pending = verdigrisPendingStore;
  if (!pending) return;
  verdigrisPendingStore = null;
  try {
    const files = [VERDIGRIS_LIB, built.replace(/\.dll$/, '.pdb')];
    if (VERDIGRIS_PROVENANCE_ENFORCED) files.push(VERDIGRIS_PROVENANCE);
    storeVerdigris(pending.cache, pending.key, pending.commit, files, {
      target: VERDIGRIS_RUST_TARGET,
      rustflags: process.env.RUSTFLAGS || '',
      abi: verdigrisAbi() || null,
    });
    Juke.logger.info(`verdigris cache: stored ${pending.key}`);
  } catch (error) {
    Juke.logger.warn(`verdigris cache: store failed: ${error instanceof Error ? error.message : error}`);
  }
};

export const VerdigrisTarget = new Juke.Target({
  dependsOn: [VerdigrisBindingsCheckTarget],
  onlyWhen: () => {
    const mismatch = verdigrisProvenanceMismatch();
    // DM-only work (agents in worktrees, CI lint jobs) can reuse a prebuilt
    // library instead of compiling the whole Rust workspace.
    if (process.env.DQ_PREBUILT_VERDIGRIS === '1' && fs.existsSync(VERDIGRIS_LIB)) {
      if (mismatch) {
        Juke.logger.error(
          `verdigris: prebuilt ${VERDIGRIS_LIB} is unsafe to reuse: ${mismatch}. `
            + 'Copy its matching provenance sidecar or rebuild in this checkout.',
        );
        throw new Juke.ExitCode(1);
      }
      Juke.logger.info(`verdigris: DQ_PREBUILT_VERDIGRIS=1 — using existing ${VERDIGRIS_LIB}`);
      // Warn now (before a long compile); DreamDaemon() refuses to boot on it.
      try {
        checkVerdigrisAbi();
      } catch {
        Juke.logger.warn('verdigris: the prebuilt library does not match this tree; test/bench/server worlds will refuse to boot.');
      }
      return false;
    }
    if (verdigrisCacheHit()) return false;
    const probe = spawnSync('cargo', ['--version'], {
      stdio: 'ignore',
      shell: true,
    });
    const cargoOk = !probe.error && probe.status === 0;
    if (!cargoOk) {
      if (mismatch && fs.existsSync(VERDIGRIS_LIB)) {
        Juke.logger.error(
          `verdigris: cargo not found and ${VERDIGRIS_LIB} cannot be used: ${mismatch}. `
            + 'Install Rust or copy a matching library and provenance sidecar.',
        );
        throw new Juke.ExitCode(1);
      }
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
    if (mismatch) Juke.logger.info(`verdigris: rebuilding ${VERDIGRIS_LIB} because ${mismatch}`);
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
  // With provenance enforced, a mismatched file can have a newer mtime than every
  // source (for example a copied DLL), so force Juke to run even when its
  // timestamp check would pass.
  outputs: () =>
    !VERDIGRIS_PROVENANCE_ENFORCED
      ? [VERDIGRIS_LIB]
      : verdigrisProvenanceMismatch()
        ? []
        : [VERDIGRIS_LIB, VERDIGRIS_PROVENANCE],
  executes: async () => {
    const built = `${process.env.CARGO_TARGET_DIR || 'verdigris/target'}/${VERDIGRIS_RUST_TARGET}/release/${VERDIGRIS_LIB}`;
    if (!VERDIGRIS_PROVENANCE_ENFORCED) {
      await Juke.exec('cargo', ['build', '--release', '--target', VERDIGRIS_RUST_TARGET], { cwd: 'verdigris' });
      fs.copyFileSync(built, VERDIGRIS_LIB);
      storeVerdigrisBuild(built);
      return;
    }
    const rustflags = process.env.RUSTFLAGS || '';
    const cargoOptions = {
      cwd: 'verdigris',
      env: { ...process.env, DQ_VERDIGRIS_INPUT_HASH: verdigrisInputHash(process.cwd()) },
    };
    // Restored source files can retain old timestamps while Cargo keeps newer
    // rlibs. Clean local crates when provenance is stale, preserving cached
    // third-party dependencies.
    if (verdigrisProvenanceMismatch()) {
      const localCrates = ['vg-core', 'vg-gas', 'vg-heat', 'vg-layout', 'vg-power', 'vg-ffi', 'auxmacros', 'auxcallback', 'verdigris'];
      await Juke.exec(
        'cargo',
        ['clean', '--release', '--target', VERDIGRIS_RUST_TARGET, ...localCrates.flatMap((c) => ['-p', c])],
        cargoOptions,
      );
    }
    await Juke.exec('cargo', ['build', '--release', '--target', VERDIGRIS_RUST_TARGET], cargoOptions);
    try {
      installVerdigrisLibrary(process.cwd(), built, VERDIGRIS_LIB, VERDIGRIS_RUST_TARGET, rustflags);
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes('lacks generated exports')) throw error;
      // Cargo can report a cached release artifact as fresh after source files
      // are restored across worktrees. Rebuild the FFI crate once from scratch.
      Juke.logger.warn(`verdigris: ${error.message}; rebuilding the FFI crate`);
      await Juke.exec('cargo', ['clean', '-p', 'vg-ffi', '--release', '--target', VERDIGRIS_RUST_TARGET], cargoOptions);
      await Juke.exec('cargo', ['build', '--release', '--target', VERDIGRIS_RUST_TARGET], cargoOptions);
      installVerdigrisLibrary(process.cwd(), built, VERDIGRIS_LIB, VERDIGRIS_RUST_TARGET, rustflags);
    }
    storeVerdigrisBuild(built);
  },
});
// DQAdd End

// DQAdd Start — the analyze lint engine (tools/analyze, doc: tools/analyze/README.md). One Rust
// binary replaces tools/ci's Python lints and check_grep.sh. Like verdigris it is built when its
// sources are newer than the binary (inputs/outputs dirty-check; the target dir is excluded by
// enumerating sources). `lint`/`analyze` run it; DM-only work that has no cargo can reuse a
// prebuilt binary (DQ_ANALYZE_NO_BUILD=1 in tools/ci/analyze.sh does the same for the shell).
const ANALYZE_DIR = process.env.CARGO_TARGET_DIR
  ? `${process.env.CARGO_TARGET_DIR}`
  : 'tools/analyze/target';
const ANALYZE_BIN = `${ANALYZE_DIR}/release/${process.platform === 'win32' ? 'analyze.exe' : 'analyze'}`;

// The analyze binary is cached by content outside the worktrees (DQ_ANALYZE_CACHE, default
// E:/dq-cache/analyze-bin on Windows, else ~/.cache/dq/analyze-bin; `off` disables it), keyed by a
// hash of the engine's sources, so a fresh worktree copies the binary instead of a 2 minute cargo
// build. `<bin>.key` records which sources the binary in the target dir was built from.
const analyzeCacheDir = (): string | null => {
  const env = process.env.DQ_ANALYZE_CACHE;
  if (env === 'off' || env === '0') return null;
  if (env) return path.resolve(env);
  if (process.platform === 'win32' && fs.existsSync('E:/')) return 'E:/dq-cache/analyze-bin';
  return path.join(os.homedir(), '.cache', 'dq', 'analyze-bin');
};
const analyzeSourceKey = (): string => {
  const hash = createHash('sha256').update(`analyze-v1|${process.platform}|${process.arch}|`);
  const files = [
    'tools/analyze/Cargo.toml',
    'tools/analyze/Cargo.lock',
    'tools/analyze/build.rs',
    ...Juke.glob('tools/analyze/src/**/*.rs'),
  ]
    .map((f) => f.replace(/\\/g, '/'))
    .sort();
  for (const file of files) {
    hash.update(file);
    hash.update('|');
    try {
      // CRLF and LF checkouts of the same source share a binary.
      hash.update(fs.readFileSync(file, 'utf-8').replace(/\r\n/g, '\n'));
    } catch {
      hash.update('<missing>');
    }
    hash.update('|');
  }
  return hash.digest('hex').slice(0, 32);
};
let analyzePendingKey: string | null = null;

export const AnalyzeBuildTarget = new Juke.Target({
  onlyWhen: () => {
    const key = analyzeSourceKey();
    analyzePendingKey = key;
    const keyFile = `${ANALYZE_BIN}.key`;
    const current = fs.existsSync(ANALYZE_BIN) && fs.existsSync(keyFile) ? fs.readFileSync(keyFile, 'utf-8').trim() : null;
    if (current === key) return false;
    const cache = analyzeCacheDir();
    const cached = cache ? `${cache}/${key}/${path.basename(ANALYZE_BIN)}` : null;
    if (cached && fs.existsSync(cached)) {
      fs.mkdirSync(path.dirname(ANALYZE_BIN), { recursive: true });
      fs.copyFileSync(cached, ANALYZE_BIN);
      fs.writeFileSync(keyFile, key);
      Juke.logger.info(`analyze cache: hit ${key} (${cache})`);
      return false;
    }
    const probe = spawnSync('cargo', ['--version'], { stdio: 'ignore', shell: true });
    const cargoOk = !probe.error && probe.status === 0;
    if (!cargoOk) {
      if (!fs.existsSync(ANALYZE_BIN)) {
        Juke.logger.warn(`analyze: cargo not found and ${ANALYZE_BIN} is missing; the lint engine cannot run. Install rustup (see verdigris/README.md).`);
      }
      return false;
    }
    if (cache) Juke.logger.info(`analyze cache: miss ${key}; building and storing`);
    return true;
  },
  executes: async () => {
    await Juke.exec('cargo', ['build', '--release', '--manifest-path', 'tools/analyze/Cargo.toml']);
    const key = analyzePendingKey;
    if (!key) return;
    fs.writeFileSync(`${ANALYZE_BIN}.key`, key);
    const cache = analyzeCacheDir();
    if (!cache) return;
    try {
      const dir = `${cache}/${key}`;
      fs.mkdirSync(dir, { recursive: true });
      // Copy then rename, so a concurrent reader never sees a half-written binary.
      const tmp = `${dir}/.${process.pid}.tmp`;
      fs.copyFileSync(ANALYZE_BIN, tmp);
      fs.renameSync(tmp, `${dir}/${path.basename(ANALYZE_BIN)}`);
      Juke.logger.info(`analyze cache: stored ${key}`);
    } catch (error) {
      Juke.logger.warn(`analyze cache: store failed: ${error instanceof Error ? error.message : error}`);
    }
  },
});

// The generated DM and TypeScript (`analyze gen`: code/engine/_generated/*.dm, code/_generated/reads.dm,
// tgui/packages/tgui/interfaces/generated/*.d.ts) are not committed; every target that compiles or
// lints DM runs this first. `analyze gen` rewrites only the files whose text changed (so an unchanged
// tree keeps its mtimes and the .dmb caches hold) and caches its parse per file in data/analyze-cache:
// about 3 s warm, 18 s cold. It fails on a generator diagnostic (a bad declaration) or a generated
// file missing from deepquarry.dme. DQ_SKIP_GEN=1 skips it (the files must already exist).
export const GenTarget = new Juke.Target({
  dependsOn: [AnalyzeBuildTarget],
  executes: async () => {
    if (process.env.DQ_SKIP_GEN === '1') {
      Juke.logger.warn('gen: DQ_SKIP_GEN=1, not regenerating code/engine/_generated');
      return;
    }
    if (!fs.existsSync(ANALYZE_BIN)) {
      if (fs.existsSync('code/engine/_generated/declare.dm')) {
        Juke.logger.warn(`gen: no analyze binary (${ANALYZE_BIN}); compiling the generated files already on disk, which may be stale`);
        return;
      }
      Juke.logger.error('gen: the generated DM is missing and the analyze engine cannot be built (install cargo, see verdigris/README.md)');
      throw new Juke.ExitCode(1);
    }
    const started = Date.now();
    const result = spawnSync(ANALYZE_BIN, ['gen'], { encoding: 'utf-8', maxBuffer: 64 * 1024 * 1024 });
    const lines = `${result.stdout || ''}${result.stderr || ''}`.split(/\r?\n/).filter((l) => l && !l.startsWith('fresh '));
    const written = lines.filter((l) => l.startsWith('wrote '));
    const other = lines.filter((l) => !l.startsWith('wrote '));
    if (result.error || result.status !== 0) {
      for (const line of lines) console.log(line);
      Juke.logger.error('gen: `analyze gen` failed (see the diagnostics above)');
      throw new Juke.ExitCode(1);
    }
    for (const line of other) console.log(line);
    Juke.logger.info(`gen: ${written.length} generated file(s) rewritten in ${((Date.now() - started) / 1000).toFixed(1)} s`);
  },
});

// `tools/build/build.sh dmb-check`: the Codex native compiler's syntax check (tools/dmb, `dm-compile check`) over
// deepquarry.dme, about 14 s instead of DreamMaker's 70-110 s. It only preprocesses and parses (no type or proc
// resolution), so it catches a broken macro, bracket or include before the real compile, not a bad path. It is an
// optional pre-check: `DQ_DMB_PRECHECK=1` runs it before dm-test's compile; DreamMaker stays the real build.
// Known parser gaps (false positives on code DreamMaker accepts) are listed in tools/dmb/precheck_known.txt and
// ignored. The binary is built into DQ_DMB_TARGET (default E:/dq-cache/dmb-target, else tools/dmb/target).
const DMB_TARGET = process.env.DQ_DMB_TARGET || (process.platform === 'win32' && fs.existsSync('E:/') ? 'E:/dq-cache/dmb-target' : 'tools/dmb/target');
const DMB_BIN = `${DMB_TARGET}/release/${process.platform === 'win32' ? 'dm-compile.exe' : 'dm-compile'}`;
export const DmbCheckTarget = new Juke.Target({
  dependsOn: () => [GenTarget],
  executes: async () => {
    if (!fs.existsSync(DMB_BIN)) {
      Juke.logger.info(`dmb-check: building ${DMB_BIN} (once, about 2 minutes)`);
      await Juke.exec('cargo', ['build', '--release', '-q', '--manifest-path', 'tools/dmb/Cargo.toml', '-p', 'dm-compile'], {
        env: { ...process.env, CARGO_TARGET_DIR: DMB_TARGET },
      });
    }
    const started = Date.now();
    const result = spawnSync(DMB_BIN, ['check', `${DME_NAME}.dme`], {
      encoding: 'utf-8',
      maxBuffer: 64 * 1024 * 1024,
      env: { ...process.env, DM_CHECK_MAX_SOURCE_BYTES: process.env.DM_CHECK_MAX_SOURCE_BYTES || '200000000' },
    });
    let known: string[] = [];
    try {
      known = fs.readFileSync('tools/dmb/precheck_known.txt', 'utf-8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
    } catch {
      // no list
    }
    const diagnostics = `${result.stdout || ''}${result.stderr || ''}`.split(/\r?\n/).filter((l) => l.startsWith('Diagnostic'));
    const fresh = diagnostics.filter((d) => !known.some((k) => d.includes(k)));
    for (const d of diagnostics) console.log(fresh.includes(d) ? d : `${d} (known parser gap)`);
    Juke.logger.info(`dmb-check: ${diagnostics.length} diagnostic(s), ${fresh.length} new, in ${((Date.now() - started) / 1000).toFixed(1)} s`);
    if (result.error) throw result.error;
    if (fresh.length) {
      Juke.logger.error('dmb-check: the native syntax check found errors (DreamMaker would likely fail too)');
      throw new Juke.ExitCode(1);
    }
  },
});

// `tools/build/build.sh analyze` runs every engine lint (what tools/ci/check_ratchets.sh and
// tools/ci/check_grep.sh wrap); extra arguments go to `analyze check` (e.g. --lint scheduler).
export const AnalyzeTarget = new Juke.Target({
  dependsOn: [GenTarget], // some lints read the generated DM (sem/reads)
  executes: async ({ args }) => {
    if (!fs.existsSync(ANALYZE_BIN)) {
      Juke.logger.warn('analyze: no binary, skipping the engine lints');
      return;
    }
    await Juke.exec(ANALYZE_BIN, ['check', ...(args || [])]);
  },
});
// DQAdd End

// DreamDaemon security for test, bench and run worlds. -trusted makes BYOND show a
// "Proceed with trusted mode?" dialog for any .dmb path it hasn't been told to
// trust, which hangs headless runs in new worktrees forever. DQ_DD_SECURITY=safe
// runs without it (safe mode still allows files and DLLs inside the world folder).
// Every world defaults to safe, including the local run target: -trusted shows a modal
// "Proceed with trusted mode?" dialog that halts unattended runs. Set DQ_DD_SECURITY=trusted
// to opt back in for a run that really needs it.
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
    GenTarget, // DreamChecker runs beside DreamMaker below (it used to run first, ~45 s on its own)
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
    // Production build: no DEBUG (no runtime line numbers, ~56 MB less at world
    // load; doc/rewrite/init_and_turfs.md §0.5). Pass -D DEBUG to get them back.
    // DreamChecker lints the same tree while DreamMaker compiles it. Either failing fails the target, and a
    // DreamChecker failure deletes the fresh .dmb so the next run cannot skip this target as up to date.
    const checker = findDreamChecker();
    if (!checker) {
      Juke.logger.info('dreamchecker not found on PATH, DREAMCHECKER_EXE, or ~/SpacemanDMM — skipping DM lint (install via tools/ci/install_spaceman_dmm.sh)');
    }
    const results = await Promise.allSettled([
      checker ? runDreamChecker().then(() => Juke.logger.info('dream-checker: passed')) : Promise.resolve(),
      DreamMaker(`${DME_NAME}.dme`, {
        defines: ['CBT', ...get(DefineParameter)],
        warningsAsErrors: get(WarningParameter).includes('error'),
        ignoreWarningCodes: get(NoWarningParameter),
        namedDmVersion: get(DmVersionParameter),
      }),
    ]);
    if (results[0].status === 'rejected') {
      fs.rmSync(`${DME_NAME}.dmb`, { force: true });
      Juke.logger.error('dream-checker failed (see above); the .dmb was removed');
      throw results[0].reason;
    }
    if (results[1].status === 'rejected') throw results[1].reason;
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
/** `dm-test --shards=N`: boots N DreamDaemon worlds instead of one.
 * `--shards=0` means "auto": size it from currently-free dd-slots (see
 * pickAutoShardCount()). Omitted, it defaults to defaultShardCount() (cores
 * minus one, capped at 4); `--shards=1` is the single-world mode. See
 * doc/testing.md "Sharded runs". */
export const ShardsParameter = new Juke.Parameter({ type: 'number' });
/** `dm-test --exhaustive`: shorthand for `--tier=all`. */
export const ExhaustiveParameter = new Juke.Parameter({ type: 'boolean' });
/** `dm-test --profile-tests`: write BYOND's proc profile for each test to
 * data/logs/<run>/profile/<test>.json (see dq_test_write_profile()). */
export const ProfileTestsParameter = new Juke.Parameter({ type: 'boolean' });

/** Sizes `dm-test --shards=0` (auto) from a snapshot of currently-free
 * dd-slots (lib/dd_slot.ts) -- "sized by dd-slot availability". Clamped to
 * [2, 6]: below 2 there's nothing to shard, and above 6 per-shard
 * boot/settle overhead and the bin-packer's coarsening returns start to
 * outweigh the extra parallelism for this suite's size. It's a
 * point-in-time read, not a reservation -- by the time each shard actually
 * calls acquireDdSlot(), another process may have taken a slot; shards
 * beyond what's free just queue like any acquireDdSlot() caller does. */
function pickAutoShardCount(): number {
  const priority = process.env.DQ_DD_PRIORITY === '1';
  const free = countFreeDdSlots(priority);
  const count = Math.min(Math.max(free, 2), 6);
  Juke.logger.info(`dm-test --shards=0 (auto): ${free} dd-slot(s) free right now -> using ${count} shard(s).`);
  return count;
}
export const BaseParameter = new Juke.Parameter({ type: 'string' });
export const HeadParameter = new Juke.Parameter({ type: 'string' });
export const ThresholdParameter = new Juke.Parameter({ type: 'number' });
export const FailOnRegressionParameter = new Juke.Parameter({ type: 'boolean' });
export const AllParameter = new Juke.Parameter({ type: 'boolean' });
export const RefParameter = new Juke.Parameter({ type: 'string' });
export const ExclusiveParameter = new Juke.Parameter({ type: 'boolean' });

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
  daemonExitCode: number | null;
  daemonSignal: string | null;
  daemonReason: string | null;
  daemonError: string | null;
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
  let daemonExitCode: number | null = null;
  let daemonSignal: string | null = null;
  let daemonReason: string | null = null;
  let daemonError: string | null = null;
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
      // A profiled bench also profiles global variable initialisation and the
      // compiled map load, which run before any DM code could start it.
      ...(worldParams.bench_profile ? ['-profile'] : []),
      '-params',
      params,
    );
    killedByWatchdog = !!result.killedByWatchdog;
    daemonExitCode = result.code;
    daemonSignal = result.signal;
    daemonReason = result.watchdogReason ?? null;
  } catch (error) {
    // DreamDaemon exits non-zero even on clean runs; the files below decide.
    // The error is kept for the benchmark diagnostics.
    daemonError = String(error);
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
    daemonExitCode,
    daemonSignal,
    daemonReason,
    daemonError,
  };
}

/** Keep every benchmark boot's outputs before the next boot clears shared paths. */
function saveBenchIterationDiagnostics(runId: string, iteration: number, run: WorldRun): string {
  const dest = `data/bench/iterations/${runId}/iteration${iteration}`;
  fs.mkdirSync(dest, { recursive: true });
  writeJson(`${dest}/runner.json`, {
    duration_seconds: run.durationSeconds,
    clean: run.clean,
    killed_by_watchdog: run.killedByWatchdog,
    daemon_exit_code: run.daemonExitCode,
    daemon_signal: run.daemonSignal,
    daemon_reason: run.daemonReason,
    daemon_error: run.daemonError,
    has_test_results: run.results !== null,
    has_benchmark_results: fs.existsSync('data/bench/scenarios.json'),
  });
  for (const source of ['data/unit_tests.json', 'data/bench/scenarios.json', 'data/bench/process.json']) {
    if (fs.existsSync(source)) fs.copyFileSync(source, `${dest}/${path.basename(source)}`);
  }
  const logSource = 'data/logs/ci';
  if (fs.existsSync(logSource)) {
    fs.cpSync(logSource, `${dest}/logs`, {
      recursive: true,
      filter: (source) => !path.relative(logSource, source).split(path.sep).includes('profiler'),
    });
  }
  return dest;
}

// ---------------------------------------------------------------------------
// Isolated test worlds. Several agents run focused tests at once, from the
// same or different worktrees. Each dm-test world gets its own run slot
// (data/runs/runN, claimed with an atomic mkdir lock that is reclaimed when
// its owner pid is gone), its own copy of the .dmb/.rsc (so a concurrent
// recompile never swaps the binary under a running daemon), its own log
// directory, results file and focus file, and a free TCP port picked by the
// OS. Nothing is written to a shared source file.

/** A free localhost TCP port, picked by the OS. */
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      server.close(() => resolve(port));
    });
  });
}

function pidAlive(pid: number): boolean {
  if (!pid || Number.isNaN(pid)) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

type RunSlot = { tag: string; dir: string; release: () => void };

/** Claims data/runs/runN for this process. */
function acquireRunSlot(): RunSlot {
  fs.mkdirSync('data/runs', { recursive: true });
  for (let k = 1; k <= 64; k++) {
    const tag = `run${k}`;
    const lock = `data/runs/${tag}.lock`;
    try {
      fs.mkdirSync(lock);
    } catch {
      let owner = 0;
      try {
        owner = Number(fs.readFileSync(`${lock}/pid`, 'utf-8').trim());
      } catch {
        // lock without a pid yet: its owner is mid-claim, or died mid-claim
        try {
          if (Date.now() - fs.statSync(lock).mtimeMs < 60_000) continue;
        } catch {
          continue;
        }
      }
      if (pidAlive(owner)) continue;
      fs.rmSync(lock, { recursive: true, force: true });
      try {
        fs.mkdirSync(lock);
      } catch {
        continue;
      }
    }
    fs.writeFileSync(`${lock}/pid`, String(process.pid));
    const dir = `data/runs/${tag}`;
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    let released = false;
    const release = () => {
      if (released) return;
      released = true;
      fs.rmSync(lock, { recursive: true, force: true });
    };
    process.on('exit', release);
    return { tag, dir, release };
  }
  Juke.logger.error('No free test run slot under data/runs (64 in use).');
  throw new Juke.ExitCode(1);
}

/** Hard-links `from` to `to` (replacing `to`), falling back to a copy where
 * links aren't possible (another volume, a filesystem without them). */
function linkOrCopy(from: string, to: string): void {
  fs.rmSync(to, { force: true });
  try {
    fs.linkSync(from, to);
  } catch {
    fs.copyFileSync(from, to);
  }
}

/** Default hard timeout for a focused run; the full suite keeps lib/byond.ts's 120 minutes. */
const FOCUSED_TIMEOUT_MINUTES = Number(process.env.DQ_FOCUS_TIMEOUT_MINUTES) || 15;

type IsolatedRun = WorldRun & { logDir: string };

/**
 * Boots `dmbFile` in its own run slot (see above). `focus` lists test type
 * paths to run (passed through the test-focus world param); null runs the
 * whole suite. Always returns; a hung world is killed at the hard timeout
 * and reported as killedByWatchdog.
 */
async function runIsolatedTestWorld(
  dmbFile: string,
  dmVersion: string | null,
  worldParams: Record<string, string>,
  focus: string[] | null,
  options: { watchdogTimeoutMs?: number; sampler?: ProcessSampler; label?: string; linkFrom?: string } = {},
): Promise<IsolatedRun> {
  const slot = acquireRunSlot();
  const base = dmbFile.replace(/\.dmb$/, '');
  const runBase = `${base}.${slot.tag}`;
  const logDir = `data/logs/${slot.tag}`;
  const resultsFile = `${slot.dir}/unit_tests.json`;
  try {
    fs.rmSync(logDir, { recursive: true, force: true });
    // DreamDaemon keeps icons made at runtime in <world>.dyn.rsc beside the
    // .dmb. Run slots are reused, so without this a world inherited the last
    // one's cache, possibly from another build ("failed to write new icon").
    fs.rmSync(`${runBase}.dyn.rsc`, { force: true });
    if (options.linkFrom) {
      // A sharded run's private copy (see runSharded()): hard links, so N
      // shards don't each copy the ~270 MB .dmb/.rsc again.
      linkOrCopy(`${options.linkFrom}.dmb`, `${runBase}.dmb`);
      linkOrCopy(`${options.linkFrom}.rsc`, `${runBase}.rsc`);
    } else {
      fs.copyFileSync(`${base}.dmb`, `${runBase}.dmb`);
      fs.copyFileSync(`${base}.rsc`, `${runBase}.rsc`);
    }
    // Generated spritesheets and the asset caches go to a directory per run
    // slot (SPRITESHEET_DIR): worlds in one worktree -- a sharded run, or two
    // focused runs -- otherwise write the same data/spritesheets files at once.
    const spritesheetDir = `data/spritesheets/${slot.tag}/`;
    fs.mkdirSync(spritesheetDir, { recursive: true });
    const params: Record<string, string> = {
      'log-directory': slot.tag,
      'unit-tests-file': resultsFile,
      'spritesheet-dir': spritesheetDir,
      ...worldParams,
    };
    if (focus) {
      const focusFile = `${slot.dir}/focus.txt`;
      fs.writeFileSync(focusFile, `${focus.join('\n')}\n`);
      params['test-focus'] = focusFile;
    }
    const port = await freePort();
    Juke.logger.info(
      `Test world ${slot.tag}${options.label ? ` (${options.label})` : ''}: ${runBase}.dmb on port ${port}, logs in ${logDir}.`,
    );
    const started = Date.now();
    let killedByWatchdog = false;
    let daemonExitCode: number | null = null;
    let daemonSignal: string | null = null;
    let daemonReason: string | null = null;
    let daemonError: string | null = null;
    try {
      const result = await DreamDaemon(
        {
          dmbFile: `${runBase}.dmb`,
          namedDmVersion: dmVersion,
          watchdogFile: resultsFile,
          watchdogTimeoutMs: options.watchdogTimeoutMs ?? (focus ? FOCUSED_TIMEOUT_MINUTES * 60 * 1000 : undefined),
          onSpawn: options.sampler ? (pid) => options.sampler?.start(pid) : undefined,
        },
        String(port),
        '-close',
        ddSecurityFlag(),
        '-verbose',
        '-params',
        new URLSearchParams(params).toString(),
      );
      killedByWatchdog = !!result.killedByWatchdog;
      daemonExitCode = result.code;
      daemonSignal = result.signal;
      daemonReason = result.watchdogReason ?? null;
    } catch (error) {
      // DreamDaemon exits non-zero even on clean runs; the files below decide.
      daemonError = String(error);
    }
    let cleanText: string | null = null;
    try {
      cleanText = fs.readFileSync(`${logDir}/clean_run.lk`, 'utf-8');
    } catch {
      // not clean
    }
    let results: Record<string, UnitTestEntry> | null = null;
    try {
      results = JSON.parse(fs.readFileSync(resultsFile, 'utf-8'));
    } catch {
      // the world died before finishing
    }
    const processSummary = options.sampler ? options.sampler.stop() : null;
    return {
      clean: cleanText !== null,
      cleanText,
      results,
      durationSeconds: (Date.now() - started) / 1000,
      process: processSummary,
      samples: options.sampler?.samples ?? [],
      killedByWatchdog,
      daemonExitCode,
      daemonSignal,
      daemonReason,
      daemonError,
      logDir,
    };
  } finally {
    await removeDerivedArtifacts(`${runBase}.dmb`);
    await removeDerivedArtifacts(`${runBase}.rsc`);
    await removeDerivedArtifacts(`${runBase}.dyn.rsc`);
    slot.release();
  }
}

/**
 * The boot gate's verdict (unit_test_boot_gate(), doc/rewrite/boot_gate.md): a world that logged a runtime or a
 * warning before its first test fails the run, and this says so on its own line so the author of a focused run
 * does not take it for their test's failure. Returns whether the boot was clean (true when no report was written).
 */
function reportBootGate(logDir: string): boolean {
  const file = `${logDir}/boot_report.json`;
  if (!fs.existsSync(file)) return true;
  try {
    const report = JSON.parse(fs.readFileSync(file, 'utf-8'));
    if (!report.runtimes && !report.warnings) return true;
    Juke.logger.error(
      `BOOT GATE: the world logged ${report.runtimes} runtime(s) and ${report.warnings} warning(s) before the first test. `
        + `This fails every run until fixed; it is not your test (unless your change runs at boot). See ${file}`
        + (report.runtimes ? ` and ${logDir}/runtime-errors.log` : '')
        + '.',
    );
    for (const line of report.first_warnings || []) console.error(`  boot warning: ${line}`);
    if (report.runtimes && fs.existsSync(`${logDir}/runtime-errors.log`)) {
      console.error(fs.readFileSync(`${logDir}/runtime-errors.log`, 'utf-8').split(/\r?\n/).slice(0, 40).join('\n'));
    }
    return false;
  } catch {
    return true;
  }
}

function printLogTails(logDir = 'data/logs/ci', lineCount = 80): void {
  for (const logFile of [`${logDir}/tests.log`, `${logDir}/runtime.log`, `${logDir}/world.log`]) {
    if (!fs.existsSync(logFile)) continue;
    const lines = fs.readFileSync(logFile, 'utf-8').trim().split(/\r?\n/);
    Juke.logger.error(`Last output from ${logFile}:`);
    console.error(lines.slice(-lineCount).join('\n'));
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

/** `dm-test --focus=/datum/unit_test/a,/datum/unit_test/b`: run only these
 * tests. Passed to the world as the test-focus param, so no source file is
 * edited and the compiled .dmb is the same for every focus set. */
export const FocusParameter = new Juke.Parameter({ type: 'string[]' });

function focusedTestNames(get: any): string[] | null {
  // Accepts full paths or bare names (dq_foo, which is what tools/dq_focused_test.sh passes).
  // `--focus=@file` reads the names from a file, one per line (or comma separated): tools/dq_focused_test.sh
  // passes a long list that way, since a Windows command line stops at 8191 characters.
  const names = (get(FocusParameter) as string[])
    .flatMap((s) => (s.startsWith('@') ? fs.readFileSync(s.slice(1), 'utf-8').split(/[\r\n,]+/) : s.split(',')))
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => (s.startsWith('/datum/unit_test/') ? s : `/datum/unit_test/${s.replace(/^\/+/, '')}`));
  for (const name of names) {
    if (!/^\/datum\/unit_test\/[A-Za-z0-9_/]+$/.test(name)) {
      Juke.logger.error(`--focus: ${name} is not a /datum/unit_test path.`);
      throw new Juke.ExitCode(2);
    }
  }
  return names.length ? names : null;
}

function reportFocus(focus: string[] | null = null): void {
  if (focus) {
    Juke.logger.warn(`Focused unit-test run (${focus.length}, via --focus): ${focus.join(', ')}`);
    return;
  }
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
  if (!run.results) {
    if (!run.killedByWatchdog) Juke.logger.error('Unit-test summary: FAILED, the world exited without writing results.');
    return null;
  }
  recordSweepHashes(run.results);
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

// DEBUG (line numbers in runtimes) is off in the production .dmb: it costs
// ~56 MB at world load (doc/rewrite/init_and_turfs.md §0.5). Test, bench and
// autowiki builds turn it back on here; a local dev build can pass -D DEBUG.
const TEST_DEFINES = ['CBT', 'CIBUILDING', 'CITESTING', 'DEBUG'];

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

/** The unit-test source files the build includes (`#include`d from
 * code/modules/unit_tests/_unit_tests.dm). A file left out of it declares
 * types the world doesn't have, so the source scans below skip it. */
function includedUnitTestFiles(): string[] {
  const dir = 'code/modules/unit_tests';
  const text = fs.readFileSync(`${dir}/_unit_tests.dm`, 'utf-8');
  const files: string[] = [];
  for (const match of text.matchAll(/^\s*#include\s+"([^"]+\.dm)"/gm)) {
    const file = `${dir}/${match[1].replace(/\\/g, '/')}`;
    if (fs.existsSync(file)) files.push(file);
  }
  return files;
}

/** Every declared unit-test type, the file it's declared in, and its
 * inferred domain -- a source scan (see enumerateUnitTestTypes()'s doc), not
 * a world boot. */
function enumerateUnitTestsWithDomain(): { name: string; file: string; domain: string }[] {
  // Bare `/datum/unit_test/foo` lines and `/datum/unit_test/foo/Run()` definitions.
  const TYPE_DECL = /^(\/datum\/unit_test\/[A-Za-z0-9_/]+?)(?:\/Run\(\))?$/;
  const out: { name: string; file: string; domain: string }[] = [];
  const seen = new Set<string>();
  for (const file of includedUnitTestFiles()) {
    const domain = classifyDomain(file);
    for (const line of fs.readFileSync(file, 'utf-8').split(/\r?\n/)) {
      const match = TYPE_DECL.exec(line.trim());
      if (!match || seen.has(match[1])) continue;
      seen.add(match[1]);
      out.push({ name: match[1], file, domain });
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
export const IncrementalParameter = new Juke.Parameter({ type: 'boolean' });

const SWEEP_HASH_CACHE_FILE = `${DMB_CACHE_DIR}/sweep-hashes.json`;

/**
 * Sweep tests eligible for `--incremental` skipping, mapped to the source
 * paths that determine their outcome. A sweep NOT in this map is never
 * skipped. This starts EMPTY on purpose, not as a placeholder:
 *
 * Every sweep here iterates `subtypesof()`/`typesof()` of some root and
 * reads `initial()` var values (or property-provider-derived values) per
 * type. That means its true input set is "every file that declares a
 * subtype of the root, anywhere in the tree" -- for dq_lifecycle_sandbox and
 * dq_state_latent_round_trip that's any /atom/movable subtype; a first
 * attempt at scoping all_clothing_shall_be_valid to
 * code/modules/clothing/ and dq_property_type_values_valid to
 * code/datums/properties/ turned out to be exactly this mistake:
 * /obj/item/clothing subtypes (and the vars property providers read) are
 * declared all over the tree (cult items, changeling powers, holiday
 * events, ...), so hashing only those folders would have silently skipped
 * a sweep after a change to a file outside them -- a false skip that hides
 * a real regression, the one thing "any doubt -> recheck" exists to
 * prevent. Getting this right needs a real type -> declaring-file map (a
 * source-level index, or a boot-time dump), not a hand-curated folder
 * list; that hasn't been built yet. Add an entry here only once you have
 * one for that sweep's actual type universe -- until then this map stays
 * empty and `--incremental` runs the sweeps in full, same as `--full`.
 */
const SWEEP_INCREMENTAL_SCOPE: Record<string, string[]> = {};

/** Content hash of every file under any of `paths` (a file, or a directory
 * walked recursively via Juke.glob), sorted for a stable result. */
function hashPaths(paths: string[]): string {
  const files = new Set<string>();
  for (const p of paths) {
    if (fs.existsSync(p) && fs.statSync(p).isFile()) {
      files.add(p);
      continue;
    }
    for (const f of Juke.glob(`${p.replace(/\/$/, '')}/**/*`)) {
      if (fs.statSync(f).isFile()) files.add(f);
    }
  }
  const hash = createHash('sha256');
  for (const f of [...files].sort()) {
    hash.update(f);
    hash.update(fs.readFileSync(f));
  }
  return hash.digest('hex');
}

type SweepHashCache = Record<string, string>;

function readSweepHashCache(): SweepHashCache {
  try {
    return readJson<SweepHashCache>(SWEEP_HASH_CACHE_FILE);
  } catch {
    return {};
  }
}

/** Eligible sweeps whose scope is byte-identical to the last passing run's
 * (per readSweepHashCache()) -- safe to skip under `--incremental`. Never
 * called for `--full`/no-flag/master runs; those always run everything. */
function incrementalSkips(): Set<string> {
  const cache = readSweepHashCache();
  const skip = new Set<string>();
  for (const [name, paths] of Object.entries(SWEEP_INCREMENTAL_SCOPE)) {
    const hash = hashPaths(paths);
    if (cache[name] === hash) skip.add(name);
  }
  if (skip.size) {
    Juke.logger.info(`--incremental: skipping ${skip.size} sweep(s) with unchanged inputs: ${[...skip].join(', ')}.`);
  }
  return skip;
}

/** After a run, records the current input hash for every eligible sweep that
 * ACTUALLY RAN this time (skipped ones keep their existing stored hash) and
 * passed -- a failed or skipped sweep's hash is left alone, so a real
 * failure keeps demanding a rerun next time rather than being masked by a
 * stale "unchanged" hash. */
function recordSweepHashes(results: Record<string, UnitTestEntry>): void {
  const cache = readSweepHashCache();
  let changed = false;
  for (const [name, paths] of Object.entries(SWEEP_INCREMENTAL_SCOPE)) {
    const entry = results[name];
    if (!entry || entry.status !== 0) continue; // didn't run, or didn't pass
    cache[name] = hashPaths(paths);
    changed = true;
  }
  if (changed) {
    fs.mkdirSync(DMB_CACHE_DIR, { recursive: true });
    writeJson(SWEEP_HASH_CACHE_FILE, cache);
  }
}

type TestTier = 'normal' | 'all' | 'exhaustive' | 'e0';

/** `--tier=`: `normal` (the default: every integration merge), `all` (normal
 * plus the exhaustive whole-type sweeps: CI and nightly), `exhaustive`
 * (only those sweeps) or `e0` (only the E0 proofs, which cannot pass until
 * the engines land: no other tier runs them, doc/testing.md "The E0 proofs").
 * The older names still work: fast = normal,
 * full = all, sweep = exhaustive. `--exhaustive` is shorthand for `--tier=all`.
 * The world does the filtering (the test-tier world param against each
 * test's `tier` var); a --focus run ignores the tier and runs what it names. */
function resolveTier(get: any): TestTier {
  if (get(ExhaustiveParameter)) return 'all';
  const raw = ((get(TierParameter) as string | null) ?? 'normal').toLowerCase();
  const aliases: Record<string, TestTier> = {
    normal: 'normal', fast: 'normal', all: 'all', full: 'all', exhaustive: 'exhaustive', sweep: 'exhaustive', e0: 'e0',
  };
  const tier = aliases[raw];
  if (!tier) {
    Juke.logger.error(`--tier=${raw}: expected normal, all, exhaustive or e0.`);
    throw new Juke.ExitCode(2);
  }
  return tier;
}

/** A predicate over unit-test type paths for a var declared in test type
 * bodies, by source scan: the nearest `<varName> = ...` line in the type's own
 * body or its closest ancestor test type's body decides, mirroring DM var
 * inheritance (so a `.../representative` subtype that sets the var back under
 * its parent wins). `isTrue` maps the declared value text to the answer; a type
 * with no declaration up its chain gets `fallback`. */
function declaredVarPredicate(varName: string, isTrue: (value: string) => boolean, fallback = false): (name: string) => boolean {
  const TYPE_DECL = /^\/datum\/unit_test\/[A-Za-z0-9_/]+$/;
  const VAR_LINE = new RegExp(`^\\s+${varName}\\s*=\\s*([A-Za-z0-9_]+)`);
  const declared = new Map<string, boolean>();
  for (const file of includedUnitTestFiles()) {
    let current: string | null = null;
    for (const line of fs.readFileSync(file, 'utf-8').split(/\r?\n/)) {
      const trimmed = line.trimEnd();
      if (TYPE_DECL.test(trimmed)) {
        current = trimmed;
        continue;
      }
      if (/^\S/.test(trimmed)) {
        current = null;
        continue;
      }
      const match = current ? VAR_LINE.exec(trimmed) : null;
      if (match && current) declared.set(current, isTrue(match[1]));
    }
  }
  return (name: string) => {
    for (let path = name; path.length > '/datum/unit_test'.length; path = path.slice(0, path.lastIndexOf('/'))) {
      const value = declared.get(path);
      if (value !== undefined) return value;
    }
    return fallback;
  };
}

/** Whether a unit-test type is in the exhaustive tier (its `tier` var). */
function exhaustiveTestPredicate(): (name: string) => boolean {
  return declaredVarPredicate('tier', (v) => v === 'TEST_TIER_EXHAUSTIVE');
}

/** Whether a unit-test type is a sweep test (`is_sweep_test`): it runs in every
 * shard and slices its own work through sweep_types()/sweep_owns(). */
function sweepTestPredicate(): (name: string) => boolean {
  return declaredVarPredicate('is_sweep_test', (v) => v === 'TRUE' || v === '1');
}

/** Whether a unit-test type is an E0 proof (its `tier` var is TEST_TIER_E0). */
function e0TestPredicate(): (name: string) => boolean {
  return declaredVarPredicate('tier', (v) => v === 'TEST_TIER_E0');
}

/** The E0 proofs belong to the `e0` tier alone: `all` does not include them. */
function tierIncludes(tier: TestTier, exhaustive: boolean, e0 = false): boolean {
  if (e0) return tier === 'e0';
  if (tier === 'e0') return false;
  if (tier === 'all') return true;
  return exhaustive ? tier === 'exhaustive' : tier === 'normal';
}

/** World params every dm-test world gets: the tier, and --profile-tests. */
function testWorldParams(get: any): Record<string, string> {
  const params: Record<string, string> = { 'test-tier': resolveTier(get) };
  if (get(ProfileTestsParameter)) params['test-profile'] = '1';
  // `tools/dq_focused_test.sh --bless`: snapshot tests write their current rows over the recorded files
  // (code/modules/unit_tests/dq_snapshot_files.dm) instead of failing.
  if (process.env.DQ_SNAPSHOT_BLESS === '1') {
    params['snapshot-bless'] = '1';
    Juke.logger.warn('DQ_SNAPSHOT_BLESS=1: snapshot tests rewrite their recorded files; review the diff before committing.');
  }
  return params;
}

/** Resolves --domains/--affected/--incremental into an explicit test
 * selection (null = no filter), and reports what it picked. The tier is not
 * a selection: the world filters it (see resolveTier()). `--domains=a,b`
 * keeps only tests in those domains; `--affected` unions in every domain
 * touched by changed files. `--incremental` additionally drops eligible
 * sweeps whose inputs are unchanged since their last passing run (see
 * SWEEP_INCREMENTAL_SCOPE). CI and the merge-to-master run never pass these. */
function resolveTestSelection(get: any): string[] | null {
  const explicitDomains = new Set(get(DomainsParameter) as string[]);
  const affected = get(AffectedParameter) as boolean;
  const incremental = get(IncrementalParameter) as boolean;
  if (!explicitDomains.size && !affected && !incremental) return null;

  const domains = new Set(explicitDomains);
  if (affected) {
    const touched = affectedDomains();
    if (!touched.size) {
      Juke.logger.warn('--affected: no changed files found against master; running the whole tier.');
    }
    for (const d of touched) domains.add(d);
  }

  const skips = incremental ? incrementalSkips() : null;
  const all = enumerateUnitTestsWithDomain();
  const selected = all
    .filter((t) => (domains.size ? domains.has(t.domain) : true))
    .filter((t) => !skips?.has(t.name))
    .map((t) => t.name);

  Juke.logger.info(
    `Test selection: ${domains.size ? `domains=${[...domains].join(',')}` : 'all domains'}`
      + `${incremental ? ', incremental' : ''} -> ${selected.length}/${all.length} test(s).`,
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
 * under-count it everywhere else. They are found by source scan
 * (sweepTestPredicate(), each test's `is_sweep_test` var), so there is no
 * hand-kept list to fall out of sync.
 */

const SHARD_DIR = 'data/test-shards';

/** Every `/datum/unit_test/...` type declared under code/modules/unit_tests,
 * by scanning source (a bare `/datum/unit_test/foo` line, not a proc/var
 * line under it) rather than booting a world -- used to seed shard
 * assignment for tests with no historical duration yet (new tests, or a
 * fresh checkout with no data/test-runs/ history). */
function enumerateUnitTestTypes(): string[] {
  // A bare `/datum/unit_test/foo` line, or a `/datum/unit_test/foo/Run()`
  // definition (plenty of tests have only the latter). Types that aren't
  // tests (abstract parents) are harmless: the world skips them.
  const TYPE_DECL = /^(\/datum\/unit_test\/[A-Za-z0-9_/]+?)(?:\/Run\(\))?$/;
  const names = new Set<string>();
  for (const file of includedUnitTestFiles()) {
    for (const line of fs.readFileSync(file, 'utf-8').split(/\r?\n/)) {
      const match = TYPE_DECL.exec(line.trim());
      if (match) names.add(match[1]);
    }
  }
  return [...names];
}

/** Greedy bin-packing of every known non-sweep test onto `shardCount`
 * shards by historical duration (from the latest stored test run, if any),
 * heaviest first onto the currently lightest shard. Tests with no
 * historical record get a small default weight, so new tests still balance
 * instead of piling onto shard 0. */
function assignTestShards(shardCount: number, selection: Set<string> | null, tier: TestTier): string[][] {
  const shards: string[][] = Array.from({ length: shardCount }, () => []);
  const loads = new Array(shardCount).fill(0);
  const durations = new Map<string, number>();
  const isSweep = sweepTestPredicate();
  // Each test's newest recorded duration, from the last 30 runs: the newest
  // run alone is often a focused run of a handful of tests, or a normal-tier
  // run that never ran the exhaustive tests an `--tier=all` run has to place.
  const runs = listRuns(TEST_RUNS_DIR);
  for (let i = runs.length - 1; i >= Math.max(runs.length - 30, 0); i--) {
    let run: TestRun;
    try {
      run = readJson<TestRun>(runs[i]);
    } catch {
      continue;
    }
    for (const [name, entry] of Object.entries(run.tests)) {
      if (!durations.has(name) && !isSweep(name)) durations.set(name, entry.duration_ds ?? 1);
    }
  }
  // Only test types the source scan finds: a run record also holds synthetic
  // entries (the harness's own checks), which no world could run.
  const known = new Set<string>();
  for (const name of enumerateUnitTestTypes()) {
    if (!isSweep(name)) known.add(name);
  }
  if (selection) for (const name of [...known]) if (!selection.has(name)) known.delete(name);
  const isExhaustive = exhaustiveTestPredicate();
  const isE0 = e0TestPredicate();
  for (const name of [...known]) if (!tierIncludes(tier, isExhaustive(name), isE0(name))) known.delete(name);
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

type ShardRun = WorldRun & { index: number; logDir: string };

/** Boots one shard's world through runIsolatedTestWorld(): its own run slot
 * (data/runs/runN lock + directory), .dmb/.rsc copy, free TCP port, log
 * directory and results file, so N shards -- and anyone else's test worlds in
 * the same worktree -- never share a path or port. A machine-wide dd-slot
 * (lib/dd_slot.ts) is also taken when DQ_DD_SLOT_BASE configures a shared
 * DreamDaemon budget; without one, the dd-slot fallback is per-worktree with
 * only two non-priority slots, which would serialize a 4-shard run. */
/** The per-shard DreamDaemon watchdog backstop, in minutes. Each shard does
 * roughly 1/shardCount of the work (sweeps self-divide via sweep_types(),
 * other tests are bin-packed), so the backstop scales down with shard count --
 * sqrt rather than linear, since boot overhead and a still-heavy slice don't
 * shrink that fast. A whole-tier run (no --focus/--select/--affected) gets a
 * much larger base: the normal tier on 4 shards took up to 34 min per shard on
 * a contended machine (2026-10-04), past the old 23 min default. Floored at 12
 * minutes; DQ_DD_WATCHDOG_MINUTES (lib/byond.ts) overrides it. */
function shardWatchdogMinutes(shardCount: number, wholeTier: boolean): number {
  const base = wholeTier ? 120 : 45;
  return Math.max(base / Math.sqrt(shardCount), 12);
}

async function runShardWorld(
  dmbFile: string,
  dmVersion: string | null,
  shardIndex: number,
  shardCount: number,
  testsFile: string,
  priority: boolean,
  worldParams: Record<string, string>,
  linkFrom: string,
  wholeTier: boolean,
): Promise<ShardRun> {
  const tag = `shard${shardIndex}`;
  fs.mkdirSync('data/bench', { recursive: true });
  const sampler = new ProcessSampler(`data/bench/process-${tag}.json`);
  const ddSlot = process.env.DQ_DD_SLOT_BASE ? await acquireDdSlot(priority) : null;
  const shardWatchdogMs = Math.round(shardWatchdogMinutes(shardCount, wholeTier) * 60 * 1000);
  try {
    const run = await runIsolatedTestWorld(
      dmbFile,
      dmVersion,
      {
        'shard-index': String(shardIndex),
        'shard-count': String(shardCount),
        'shard-tests': testsFile,
        ...worldParams,
      },
      null,
      { watchdogTimeoutMs: shardWatchdogMs, sampler, label: `${tag} of ${shardCount}`, linkFrom },
    );
    return { ...run, index: shardIndex };
  } finally {
    ddSlot?.release();
  }
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

/** Writes a test-name list under a directory private to this process, so two
 * dm-test invocations in one worktree never overwrite each other's lists. */
function writeRunList(name: string, names: string[]): string {
  const dir = `${SHARD_DIR}/${process.pid}`;
  fs.mkdirSync(dir, { recursive: true });
  const file = `${dir}/${name}`;
  fs.writeFileSync(file, names.length ? `${names.join('\n')}\n` : '');
  return file;
}

/** Default `dm-test` shard count: cores minus one (leave one for the rest of
 * the machine), capped at 4 -- past that, per-world boot overhead and the
 * heaviest single test dominate. DQ_TEST_SHARDS overrides it. */
function defaultShardCount(): number {
  const env = Number(process.env.DQ_TEST_SHARDS);
  if (Number.isInteger(env) && env >= 1) return env;
  return Math.min(Math.max(os.cpus().length - 1, 1), 4);
}

/** The `--shards=N` path for DmTestTarget: compiles once, boots N worlds in
 * parallel on the same .dmb (each in its own run slot and port), and merges
 * their results into one data/test-runs/ record. */
async function runSharded(shardCount: number, get: any): Promise<void> {
  reportFocus();
  await compileDerived(`${DME_NAME}.test.dme`, get, TEST_DEFINES);
  const priority = process.env.DQ_DD_PRIORITY === '1';
  const tier = resolveTier(get);
  const worldParams = testWorldParams(get);
  const selection = resolveTestSelection(get);
  const selectionSet = selection ? new Set(selection) : null;
  if (selection) worldParams['test-select'] = writeRunList('select.txt', selection);
  const assignment = assignTestShards(shardCount, selectionSet, tier);
  // One assignment file for every shard ("path<TAB>shard" per line): a world
  // runs what's assigned to it, and places any test the file doesn't name by
  // a hash of its path (dq_test_shard_of_unlisted()), so none is skipped.
  const assignmentFile = writeRunList(
    `shard-assignment-${shardCount}.txt`,
    assignment.flatMap((names, i) => names.map((name) => `${name}\t${i}`)),
  );
  const testFiles = assignment.map(() => assignmentFile);
  Juke.logger.info(
    `dm-test --shards=${shardCount} --tier=${tier}: `
      + `${assignment.map((a, i) => `shard ${i}: ${a.length} test(s)`).join(', ')}, `
      + `plus every sweep test in the tier in each shard${selection ? ' that matches the selection' : ''}.`,
  );
  const wholeTier = !selection;
  const watchdogMinutes = shardWatchdogMinutes(shardCount, wholeTier);
  const started = Date.now();
  // One private copy of the build for this run (a concurrent recompile in this
  // worktree must not swap the binary under running worlds), which every
  // shard's run slot hard-links. Copying it once per shard was over 1 GB of
  // synchronous writes before any world started: minutes on a busy disk.
  const privateBase = `${DME_NAME}.test.shards-${process.pid}`;
  await fs.promises.copyFile(`${DME_NAME}.test.dmb`, `${privateBase}.dmb`);
  await fs.promises.copyFile(`${DME_NAME}.test.rsc`, `${privateBase}.rsc`);
  let runs: ShardRun[];
  try {
    runs = await Promise.all(
      Array.from({ length: shardCount }, (_, i) =>
        runShardWorld(
          `${DME_NAME}.test.dmb`,
          get(DmVersionParameter),
          i,
          shardCount,
          testFiles[i],
          priority,
          worldParams,
          privateBase,
          wholeTier,
        )),
    );
  } finally {
    await removeDerivedArtifacts(`${privateBase}.dmb`);
    await removeDerivedArtifacts(`${privateBase}.rsc`);
  }
  const wallSeconds = (Date.now() - started) / 1000;
  for (const run of runs) {
    if (run.killedByWatchdog) {
      Juke.logger.error(
        `Shard ${run.index}: the DreamDaemon watchdog force-killed this world for running past its `
          + `${Math.round(watchdogMinutes)}min hard timeout (DQ_DD_WATCHDOG_MINUTES to raise it). `
          + `${run.results ? 'Partial' : 'No'} results were captured.`,
      );
    }
    if (!run.clean) {
      Juke.logger.error(`Shard ${run.index} (logs in ${run.logDir}) was not clean:`);
      printLogTails(run.logDir, 40);
      reportBootGate(run.logDir);
    }
  }
  const { results, clean, totalCpuSeconds } = mergeShardResults(runs);
  recordSweepHashes(results);
  const record = testRunRecord(
    runIdentity(get(LabelParameter)),
    get(LabelParameter),
    [...TEST_DEFINES, ...get(DefineParameter)],
    clean,
    wallSeconds,
    results,
  );
  writeJson(`${TEST_RUNS_DIR}/${record.id}.json`, record);
  const shardTimes = runs.map((r) => `${Math.round(r.durationSeconds)}s`).join('/');
  // A shard that wrote no results lost every test assigned to it: say so in
  // the summary, so its counts can't read as a complete run.
  const lost = runs.filter((r) => !r.results).map((r) => r.index);
  if (lost.length) {
    Juke.logger.error(
      `Shard(s) ${lost.join(', ')} wrote no results: their assigned tests did not run, and the counts below `
        + 'cover only the other shards.',
    );
  }
  Juke.logger.info(
    `Unit-test summary (${shardCount} shards, tier ${tier}${lost.length ? `, ${lost.length} SHARD(S) LOST` : ''}): `
      + `${record.counts.passed} passed, ${record.counts.failed} failed, `
      + `${record.counts.skipped} skipped in ${Math.round(wallSeconds)}s wall (shards ${shardTimes}) / `
      + `~${Math.round(totalCpuSeconds)}s summed CPU (saved ${TEST_RUNS_DIR}/${record.id}.json).`,
  );
  console.log(testHotspots(results, 20));
  for (const name of record.failed) {
    Juke.logger.error(`FAILED ${name}: ${results[name].message ?? ''}`);
  }
  // Keep this run's shard lists beside its record, so a failure that depends on
  // what else ran in its world can be rerun with the same set of tests
  // (`dm-test --focus=` the shard's list; the world orders tests by priority).
  const keptLists = `${SHARD_DIR}/${record.id}`;
  fs.rmSync(keptLists, { recursive: true, force: true });
  fs.renameSync(`${SHARD_DIR}/${process.pid}`, keptLists);
  if (record.failed.length) Juke.logger.info(`Each shard's test list is kept in ${keptLists}.`);
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
    FocusParameter,
    ShardsParameter,
    DomainsParameter,
    TierParameter,
    AffectedParameter,
    IncrementalParameter,
    ExhaustiveParameter,
    ProfileTestsParameter,
  ],
  dependsOn: ({ get }) => [
    get(DefineParameter).includes('ALL_MAPS') && DmMapsIncludeTarget,
    IconRepackTarget, // tests boot the world, which uses the .rsc
    ValidateDmeTarget, // catch missing includes before compiling
    VerdigrisTarget, // tests boot the world, which loads the FFI lib
    MapBoundsTarget, // tests boot the world, which reads template bounds
    process.env.DQ_DMB_PRECHECK === '1' && DmbCheckTarget, // optional 14 s syntax pre-check (tools/dmb)
  ],
  executes: async ({ get }) => {
    const focus = focusedTestNames(get);
    // Sharded by default (defaultShardCount()); --shards=1 is the single-world
    // mode, --shards=0 sizes from free dd-slots. A --focus run is one world:
    // it's a handful of tests, so extra boots would only cost time.
    const requestedShards = get(ShardsParameter);
    const shardCount = focus
      ? 1
      : requestedShards === 0
        ? pickAutoShardCount()
        : Math.max(requestedShards ?? defaultShardCount(), 1);
    if (shardCount > 1) {
      await runSharded(shardCount, get);
      return;
    }
    reportFocus(focus);
    await compileDerived(`${DME_NAME}.test.dme`, get, TEST_DEFINES);
    const selection = resolveTestSelection(get);
    const worldParams = testWorldParams(get);
    if (selection) worldParams['test-select'] = writeRunList('select.txt', selection);
    if (!focus) Juke.logger.info(`dm-test: single world, tier ${worldParams['test-tier']}.`);
    const run = await runIsolatedTestWorld(`${DME_NAME}.test.dmb`, get(DmVersionParameter), worldParams, focus);
    fs.rmSync(`${SHARD_DIR}/${process.pid}`, { recursive: true, force: true });
    if (!run.clean) {
      printLogTails(run.logDir, run.killedByWatchdog ? 40 : 80);
      reportBootGate(run.logDir);
      // The state guard (unit_test_globals_guard()): globals an earlier test left changed, the usual cause of a
      // failure that shows only in a long run.
      try {
        const leaks = fs.readFileSync(`${run.logDir}/tests.log`, 'utf-8').split(/\r?\n/).filter((l) => l.includes('STATE LEAK'));
        if (leaks.length) {
          Juke.logger.warn(`State guard: ${leaks.length} global(s) left changed by a test (suspects for an order-dependent failure):`);
          console.error(leaks.slice(0, 30).join('\n'));
        }
      } catch {
        // no tests.log
      }
    }
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
    // Juke.exec() resolves a relative `executable` (via fs.existsSync +
    // path.resolve) against ITS OWN process's cwd, not the `cwd` spawn
    // option -- so a relative script path here would almost always resolve
    // back to THIS worktree's copy (since the same relative path exists
    // here too), run it, and that script's own `cd "$(dirname "$0")"`
    // would then cd right back into this worktree, discarding `cwd:
    // worktree` entirely. The nested build would silently build and test
    // THIS worktree's checkout instead of the baseline commit's -- found by
    // actually running bench-baseline end-to-end and noticing the stored
    // baseline run's commit was this branch's HEAD, not the ref it was
    // supposed to baseline. Always pass an absolute, worktree-rooted path.
    const script = path.join(worktree, process.platform === 'win32' ? 'tools\\build\\build.bat' : 'tools/build/build.sh');
    // Juke's CLI parser treats any bare (non-dash) argv token as the start of
    // a new target, and a long flag's value only registers with `=` in the
    // same token (see doc/testing.md's "Juke options take `=`" note) -- so
    // both the flag and its value must be one token: `--label=x`, `-Dx`, never
    // `--label`, `x` or `-D`, `x` as separate argv entries, or Juke silently
    // tries to run `x` as a second, nonexistent target and the whole nested
    // invocation fails before it does anything.
    const defines = get(DefineParameter).map((d) => `-D${d}`);
    try {
      await Juke.exec(script, ['dm-test', `--label=baseline-${commit}`, ...defines], {
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
    ExclusiveParameter,
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
    const wantExclusive = !!get(ExclusiveParameter);
    let exclusiveLock: Awaited<ReturnType<typeof acquireBenchExclusiveLock>> | null = null;
    let drained = false;
    if (wantExclusive) {
      Juke.logger.info(`Acquiring the exclusive bench lock (${benchStoreDir() ? 'shared' : 'local, DQ_BENCH_STORE unset'})...`);
      exclusiveLock = await acquireBenchExclusiveLock();
      drained = await waitForDreamDaemonsToDrain(5 * 60 * 1000, 5000, (msg) => Juke.logger.info(msg));
      if (!drained) Juke.logger.warn('Timed out waiting for other DreamDaemons to drain; benchmarking under load anyway.');
    }
    const loadSampler = new LoadSampler();
    loadSampler.start();
    const iterations: BenchIteration[] = [];
    const failures: string[] = [];
    try {
      for (let i = 1; i <= warmup + runs; i++) {
        const isWarmup = i <= warmup;
        Juke.logger.info(`Benchmark iteration ${i}/${warmup + runs}${isWarmup ? ' (warm-up, not counted)' : ''}`);
        // The world writes the flight recorder of each scenario here (code/modules/benchmarks/_benchmark.dm).
        fs.rmSync('data/bench/kernel_ticks', { recursive: true, force: true });
        const run = await runTestWorld(`${DME_NAME}.bench.dmb`, get(DmVersionParameter), worldParams, true);
        const diagnostics = saveBenchIterationDiagnostics(identity.id, i, run);
        let world: WorldBenchDocument;
        try {
          world = readJson<WorldBenchDocument>('data/bench/scenarios.json');
        } catch {
          printLogTails();
          failures.push(
            `iteration ${i}: the world wrote no benchmark results `
              + `(daemon ${run.daemonReason ?? 'unknown'}, exit ${run.daemonExitCode ?? 'unknown'}, `
              + `watchdog ${run.killedByWatchdog ? 'timed out' : 'no'}; diagnostics: ${diagnostics})`,
          );
          continue;
        }
        if (run.killedByWatchdog || run.daemonError) {
          failures.push(`iteration ${i}: DreamDaemon ${run.daemonError ?? run.daemonReason ?? 'failed'}; diagnostics: ${diagnostics}`);
        }
        for (const scenario of Object.values(world.scenarios)) {
          if (scenario.status !== 'passed') {
            failures.push(`iteration ${i}: ${scenario.id} ${scenario.status}: ${scenario.error ?? ''}; diagnostics: ${diagnostics}`);
          }
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
        // The per-tick series (usage, maptick, input cost, top systems) so a regression can be opened tick by tick.
        if (fs.existsSync('data/bench/kernel_ticks')) {
          const dest = `data/bench/profiles/${identity.id}/iteration${i}`;
          fs.mkdirSync(dest, { recursive: true });
          for (const file of fs.readdirSync('data/bench/kernel_ticks')) {
            fs.copyFileSync(`data/bench/kernel_ticks/${file}`, `${dest}/kernel_ticks_${file}`);
            profiles.push(`${dest}/kernel_ticks_${file}`);
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
    } finally {
      exclusiveLock?.release();
    }
    const load: LoadContext = loadSampler.stop(true, wantExclusive && drained);
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
      load,
    };
    const runsDir = benchRunsDir();
    const file = `${runsDir}/${record.id}.json`;
    writeJson(file, record);
    for (const [scenario, metrics] of Object.entries(record.summary)) {
      console.log(`\n${scenario}`);
      for (const [name, stats] of Object.entries(metrics)) {
        const spread = stats.n > 1 ? ` ±${formatNumber(stats.stdev)}` : '';
        console.log(`  ${name.padEnd(40)} ${formatNumber(stats.median).padStart(10)} ${stats.unit}${spread}`);
      }
    }
    Juke.logger.info(
      `Saved ${file} (load: ${load.exclusive ? 'exclusive' : `cpu ${load.cpu_percent}%, +${load.other_dreamdaemon} dd/+${load.other_dm} dm/+${load.cargo_rustc} cargo-rustc`}).`,
    );
    // Prefer the stored baseline for this branch's merge-base with master
    // (see findBaselineRun in lib/bench.ts) over "whatever ran before this",
    // since a fresh worktree otherwise has nothing but its own history.
    const baseline = findBaselineRun(record.map, { label: null });
    if (baseline) {
      console.log(`\nCompared with baseline ${baseline.run.id} (commit ${baseline.commit}${baseline.isMergeBase ? ', the merge-base with master' : ', the nearest master ancestor with a stored run'}):`);
      console.log(formatComparison(compareRuns(baseline.run, record, 5), true));
    } else {
      const sameMap = listRuns(runsDir)
        .map((f) => readJson<BenchRun>(f))
        .filter((r) => r.map === record.map && r.id !== record.id);
      if (sameMap.length) {
        const previous = sameMap[sameMap.length - 1];
        Juke.logger.warn(
          `No stored baseline for this branch's merge-base with master (run 'bench-baseline' to create one). `
          + `Comparing with the previous local run ${previous.id} instead.`,
        );
        console.log(formatComparison(compareRuns(previous, record, 5), true));
      } else {
        Juke.logger.warn(`No stored baseline and no previous run for map '${record.map}' to compare with. Run 'bench-baseline' to create one.`);
      }
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
    const runsDir = benchRunsDir();
    const headFile = resolveRun(runsDir, get(HeadParameter) || 'latest');
    const head = readJson<BenchRun>(headFile);
    // --base=baseline (or no --base at all) means "this branch's stored
    // master merge-base", the same lookup `bench` itself prints after a run.
    const baseArg = get(BaseParameter);
    let base: BenchRun;
    let baseLabel: string;
    if (!baseArg || baseArg === 'baseline') {
      const baseline = findBaselineRun(head.map);
      if (!baseline) {
        Juke.logger.error(
          `No stored baseline for this branch's merge-base with master and map '${head.map}'. `
          + `Run 'bench-baseline' to create one, or pass --base=<run> to compare against something else.`,
        );
        throw new Juke.ExitCode(1);
      }
      base = baseline.run;
      baseLabel = `${base.id} (commit ${baseline.commit}${baseline.isMergeBase ? ', the merge-base with master' : ', the nearest master ancestor with a stored run'})`;
    } else {
      base = readJson<BenchRun>(resolveRun(runsDir, baseArg));
      baseLabel = base.id;
    }
    if (base.map !== head.map) Juke.logger.warn(`Comparing different maps: ${base.map} vs ${head.map}`);
    const rows = compareRuns(base, head, get(ThresholdParameter) ?? 5);
    console.log(`Base ${baseLabel}\nHead ${head.id}\n`);
    console.log(formatComparison(rows, !get(AllParameter)));
    const regressions = rows.filter((r) => r.verdict === 'regression');
    const improvements = rows.filter((r) => r.verdict === 'improvement');
    const notComparable = rows.filter((r) => r.verdict === 'not_comparable');
    Juke.logger.info(
      `${regressions.length} regression(s), ${improvements.length} improvement(s), ${notComparable.length} not comparable (load), ${rows.length} metrics compared.`,
    );
    if (get(FailOnRegressionParameter) && regressions.length) throw new Juke.ExitCode(1);
  },
});

export const BenchReportTarget = new Juke.Target({
  executes: async () => {
    const { runs, tests } = renderReport('data/bench/report.html');
    Juke.logger.info(`Wrote data/bench/report.html (${runs} benchmark runs, ${tests} test runs).`);
  },
});

/**
 * Runs the medical and combat balance harness (code/modules/balance) in a
 * -DBENCHMARK world, stores the results in data/balance/runs/ and lists what
 * changed since the previous run. `--arg scenarios=ttk,bleedout` runs a subset.
 * doc/balance_baseline.md explains the numbers.
 */
export const BalanceTarget = new Juke.Target({
  parameters: [DefineParameter, DmVersionParameter, WarningParameter, NoWarningParameter, ArgParameter, LabelParameter, ThresholdParameter],
  dependsOn: [IconRepackTarget, ValidateDmeTarget, VerdigrisTarget, MapBoundsTarget],
  executes: async ({ get }) => {
    const worldParams: Record<string, string> = { bench: 'balance' };
    for (const arg of get(ArgParameter)) {
      const [key, ...rest] = arg.split('=');
      worldParams[`bench_${key}`] = rest.join('=');
    }
    await compileDerived(`${DME_NAME}.bench.dme`, get, [...TEST_DEFINES, 'BENCHMARK']);
    const identity = runIdentity(get(LabelParameter));
    Juke.rm(BALANCE_RESULTS_FILE);
    await runTestWorld(`${DME_NAME}.bench.dmb`, get(DmVersionParameter), worldParams, false);
    await removeDerivedArtifacts('*.bench.*');
    let world: BalanceWorldDocument;
    try {
      world = readBalanceResults();
    } catch {
      printLogTails();
      Juke.logger.error(`The world wrote no ${BALANCE_RESULTS_FILE}.`);
      throw new Juke.ExitCode(1);
    }
    const failures = balanceFailures(world);
    const record: BalanceRun = { ...identity, kind: 'balance', label: get(LabelParameter), world, failures };
    const previous = listRuns(BALANCE_RUNS_DIR).map((f) => readJson<BalanceRun>(f)).filter((r) => r.world.map === world.map);
    const file = `${BALANCE_RUNS_DIR}/${record.id}.json`;
    writeJson(file, record);
    for (const scenario of Object.values(world.scenarios)) {
      console.log(`${scenario.id.padEnd(12)} ${scenario.status.padEnd(8)} ${Object.keys(scenario.results ?? {}).length} values in ${scenario.duration_seconds ?? '?'}s`);
    }
    Juke.logger.info(`Saved ${file}`);
    if (previous.length) {
      const base = previous[previous.length - 1];
      console.log(`
Changed since ${base.id}:`);
      console.log(formatBalanceChanges(compareBalance(base.world, world, get(ThresholdParameter) ?? 0)));
    }
    if (failures.length) {
      for (const failure of failures) Juke.logger.error(failure);
      throw new Juke.ExitCode(1);
    }
  },
});

/** Diffs two stored balance runs (default: previous against latest). */
export const BalanceCompareTarget = new Juke.Target({
  parameters: [BaseParameter, HeadParameter, ThresholdParameter],
  executes: async ({ get }) => {
    const base = readJson<BalanceRun>(resolveRun(BALANCE_RUNS_DIR, get(BaseParameter) || 'previous'));
    const head = readJson<BalanceRun>(resolveRun(BALANCE_RUNS_DIR, get(HeadParameter) || 'latest'));
    if (base.world.map !== head.world.map) Juke.logger.warn(`Comparing different maps: ${base.world.map} vs ${head.world.map}`);
    const changes = compareBalance(base.world, head.world, get(ThresholdParameter) ?? 0);
    console.log(`Base ${base.id}
Head ${head.id}
`);
    console.log(formatBalanceChanges(changes));
    Juke.logger.info(`${changes.length} balance number(s) changed.`);
  },
});

/**
 * Runs the benchmark for another commit (default `master`) in a reusable
 * worktree, exclusively (to keep the stored numbers meaningful), and stores
 * it so branch worktrees have a baseline to compare against (see
 * findBaselineRun in lib/bench.ts and the `bench` target's automatic
 * comparison). Mirrors TestBaselineTarget above.
 */
export const BenchBaselineTarget = new Juke.Target({
  parameters: [RefParameter, ScenarioParameter, RunsParameter, WarmupParameter, DefineParameter],
  executes: async ({ get }) => {
    const ref = get(RefParameter) || 'master';
    const commit = spawnSync('git', ['rev-parse', '--short=10', ref], { encoding: 'utf-8' }).stdout.trim();
    if (!commit) {
      Juke.logger.error(`Unknown git ref '${ref}'.`);
      throw new Juke.ExitCode(1);
    }
    if (!benchStoreDir()) {
      Juke.logger.warn(
        'DQ_BENCH_STORE is not set, so this baseline will only be visible from the current worktree. '
        + 'Set DQ_BENCH_STORE to a shared directory (see doc/testing.md) so other worktrees on this machine can find it.',
      );
    }
    const root = process.cwd();
    const worktree = path.join(os.tmpdir(), `dq-bench-baseline-${commit}`);
    if (!fs.existsSync(worktree)) {
      Juke.logger.info(`Creating baseline worktree for ${ref} (${commit}) at ${worktree}`);
      await Juke.exec('git', ['worktree', 'add', '--detach', worktree, commit]);
    } else {
      Juke.logger.info(`Reusing baseline worktree ${worktree}`);
    }
    if (fs.existsSync('icons/gen') && !fs.existsSync(path.join(worktree, 'icons/gen'))) {
      fs.cpSync('icons/gen', path.join(worktree, 'icons/gen'), { recursive: true });
    }
    // See the matching comment (and the "found by actually running this end
    // to end" story) in TestBaselineTarget above: the script path must be
    // absolute and worktree-rooted, or Juke.exec silently builds/runs THIS
    // worktree's checkout instead of the worktree passed via `cwd`.
    const script = path.join(worktree, process.platform === 'win32' ? 'tools\\build\\build.bat' : 'tools/build/build.sh');
    // See the matching comment in TestBaselineTarget above: every flag with a
    // value must be one argv token (`--x=y` / `-Dy`), never split across two.
    const defines = get(DefineParameter).map((d) => `-D${d}`);
    const scenarioArgs = get(ScenarioParameter).length ? [`--scenario=${get(ScenarioParameter).join(',')}`] : [];
    const runsArg = get(RunsParameter) != null ? [`--runs=${get(RunsParameter)}`] : [];
    const warmupArg = get(WarmupParameter) != null ? [`--warmup=${get(WarmupParameter)}`] : [];
    try {
      await Juke.exec(
        script,
        ['bench', '--exclusive', `--label=baseline-${commit}`, ...scenarioArgs, ...runsArg, ...warmupArg, ...defines],
        {
          cwd: worktree,
          shell: process.platform === 'win32',
          env: { ...process.env, CARGO_TARGET_DIR: path.join(root, 'verdigris', 'target') },
        },
      );
    } catch {
      // A failing scenario still writes a run; the check below decides.
    }
    // Don't assume the child wrote to the shared store just because
    // DQ_BENCH_STORE is set out here: the baseline commit's OWN checkout is
    // what actually builds and runs (that's the whole point), and an older
    // commit's bench.ts may predate the shared-store/--exclusive feature
    // entirely, in which case it silently ignored --exclusive and wrote to
    // its own worktree-local data/bench/runs regardless of our env (found by
    // actually baselining a commit from before this feature existed: the
    // nested run's own log showed a relative "Saved data/bench/runs/..."
    // path and no "Acquiring the exclusive bench lock" line at all). So
    // check both places and identify the right file by its own commit+label
    // fields, not by which directory we expected it in.
    const label = `baseline-${commit}`;
    const store = benchStoreDir();
    const candidateDirs = [path.join(worktree, BENCH_RUNS_DIR), ...(store ? [path.join(store, 'runs')] : [])];
    const matches = candidateDirs
      .flatMap((dir) => listRuns(dir))
      .map((file) => ({ file, run: readJson<BenchRun>(file) }))
      .filter(({ run }) => run.commit === commit && run.label === label)
      .sort((a, b) => a.run.timestamp.localeCompare(b.run.timestamp));
    if (!matches.length) {
      Juke.logger.error('The baseline bench produced no stored run (compile, boot or scenario failure). See the output above.');
      throw new Juke.ExitCode(1);
    }
    const { file: baselineFile } = matches[matches.length - 1];
    // Get it into the shared store if one is configured and it isn't there
    // already (the child may not have understood DQ_BENCH_STORE at all, as
    // above; even when it did, copying is a harmless no-op check away).
    if (store) {
      const dest = path.join(store, 'runs', path.basename(baselineFile));
      if (path.resolve(dest) !== path.resolve(baselineFile)) {
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(baselineFile, dest);
      }
      Juke.logger.info(`Saved baseline to the shared store: ${dest}`);
    } else {
      const dest = path.join(BENCH_RUNS_DIR, path.basename(baselineFile));
      if (path.resolve(dest) !== path.resolve(baselineFile)) {
        fs.mkdirSync(BENCH_RUNS_DIR, { recursive: true });
        fs.copyFileSync(baselineFile, dest);
      }
      Juke.logger.info(`Saved baseline to ${dest}`);
    }
    const record = readJson<BenchRun>(baselineFile);
    Juke.logger.info(`Baseline for ${ref} (${commit}), map ${record.map}: ${Object.keys(record.summary).length} scenario(s) with results.`);
    Juke.logger.info(`Remove the worktree when done: git worktree remove --force ${worktree}`);
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
      defines: ['CBT', 'AUTOWIKI', 'DEBUG', ...get(DefineParameter)],
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
  dependsOn: [GenTarget], // it lints the generated DM too
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
  executes: () => runDreamChecker(),
});

/** SpacemanDMM's DreamChecker over deepquarry.dme; throws on any diagnostic it fails on. */
async function runDreamChecker(): Promise<void> {
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
}
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
  dependsOn: [TguiLintTarget, DreamCheckerTarget, AnalyzeTarget], // DQAdd — DM lint via SpacemanDMM if available; the analyze engine lints
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
        ddSecurityFlag(),
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
