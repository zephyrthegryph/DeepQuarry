// Content-addressed cache of the built native compiler (tools/dmb: dmbc and dmbd), shared by every
// checkout and worktree on the machine, so a fresh worktree copies the executables instead of running a
// 3-5 minute `cargo build` and keeping its own multi-GB tools/dmb/target. Same scheme as the Verdigris
// cache (verdigris_cache.ts): the key is the git tree/blob ids at HEAD of every input the compiler is built
// from plus the platform and profile, and a checkout whose inputs differ from HEAD bypasses the cache.
//
// Layout: <cache>/<key>/release/{dmbc[.exe], dmbd[.exe], manifest.json}
// Env: DQ_DMBC_CACHE=<dir> overrides the location; DQ_DMBC_CACHE=off disables it.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { storeVerdigris, dropVerdigris, type CacheKey } from './verdigris_cache';

const CACHE_VERSION = 1;

// Everything tools/dmb/build.rs, Cargo and the `include_bytes!` of the engine template read.
export const DMBC_CACHE_INPUTS = [
  'tools/dmb/Cargo.toml',
  'tools/dmb/Cargo.lock',
  'tools/dmb/build.rs',
  'tools/dmb/src',
  'tools/dmb/crates',
  'tools/dmb/patches',
  'tools/dmb/fixtures/native_template.bin',
];

export function dmbcCacheDir(): string | null {
  const env = process.env.DQ_DMBC_CACHE;
  if (env === 'off' || env === '0') return null;
  if (env) return path.resolve(env);
  if (process.platform === 'win32' && fs.existsSync('E:/')) return 'E:/dq-cache/dmbc';
  return path.join(os.homedir(), '.cache', 'dq', 'dmbc');
}

/**
 * The one compiler binary every checkout and worktree on the machine runs, so they all share one compiler identity and
 * therefore one resident daemon: `<bin>/{dmbc,dmbd}[.exe]`, default E:/dq-cache/dmb-bin. It is a published copy, never a
 * cargo output dir: other agents point CARGO_TARGET_DIR at E:/dq-cache/dmb-target and rewrite its dmbc.exe while a compile
 * is using it (the merge gates saw ENOENT on it mid-compile). `DQ_DMBC_BIN_DIR` relocates it; `DQ_DMBC_BIN` names an
 * explicit dmbc executable instead (see `dmbcBinOverride`).
 */
export function sharedDmbcBinDir(): string {
  if (process.env.DQ_DMBC_BIN_DIR) return path.resolve(process.env.DQ_DMBC_BIN_DIR).split(path.sep).join('/');
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/dmb-bin';
  return path.join(os.homedir(), '.cache', 'dq', 'dmb-bin').split(path.sep).join('/');
}

/** Private cargo target the shared binary is built in on a cache miss (path-dependent, so shared by name not by content). */
export function sharedDmbcBuildTarget(): string {
  if (process.env.DQ_DMBC_BUILD_DIR) return path.resolve(process.env.DQ_DMBC_BUILD_DIR).split(path.sep).join('/');
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/dmb-build';
  return path.join(os.homedir(), '.cache', 'dq', 'dmb-build').split(path.sep).join('/');
}

const EXE_SUFFIX = process.platform === 'win32' ? '.exe' : '';

/**
 * The shared binary is immutable per version: `<bin>/v/<id>/{dmbc,dmbd}[.exe]`, `<id>` the content hash of the pair, and
 * `<bin>/current` names the version new compiles use. Publishing writes a new version directory and switches `current`
 * atomically; it never touches a version a compile may be running, so a republish mid-gate cannot change the executable under
 * it ("Native executable changed during compilation"). A process resolves `current` once and keeps that version for its whole
 * life (`pinnedDmbcVersion`); `unpinDmbcVersion` is for a process that has just published and wants its own result. A bin dir
 * with no `current` is the pre-versioning layout `<bin>/dmbc[.exe]`, still honoured.
 */
const pinned = new Map<string, string | null>();

export function dmbcVersionDir(binDir: string, id: string): string {
  return `${binDir}/v/${id}`;
}

export function readCurrentDmbcVersion(binDir: string = sharedDmbcBinDir()): string | null {
  try {
    const id = fs.readFileSync(`${binDir}/current`, 'utf8').trim();
    if (/^[0-9a-f]{16}$/.test(id) && fs.existsSync(`${dmbcVersionDir(binDir, id)}/dmbc${EXE_SUFFIX}`)) return id;
  } catch {
    // no pointer yet: the legacy layout
  }
  return null;
}

export function pinnedDmbcVersion(binDir: string = sharedDmbcBinDir()): string | null {
  if (!pinned.has(binDir)) pinned.set(binDir, readCurrentDmbcVersion(binDir));
  return pinned.get(binDir) ?? null;
}

export function unpinDmbcVersion(binDir: string = sharedDmbcBinDir()): void {
  pinned.delete(binDir);
}

export function sharedDmbcExe(name: 'dmbc' | 'dmbd' = 'dmbc'): string {
  const binDir = sharedDmbcBinDir();
  const id = pinnedDmbcVersion(binDir);
  return id ? `${dmbcVersionDir(binDir, id)}/${name}${EXE_SUFFIX}` : `${binDir}/${name}${EXE_SUFFIX}`;
}

/** The pointer file: changes whenever a new version is published (a Juke target output). */
export function sharedDmbcPointer(): string {
  return `${sharedDmbcBinDir()}/current`;
}

/** DQ_DMBC_BIN: run this dmbc instead of the shared binary (it is never rebuilt or restored over). */
export function dmbcBinOverride(): string | undefined {
  return process.env.DQ_DMBC_BIN ? path.resolve(process.env.DQ_DMBC_BIN) : undefined;
}

function git(root: string, args: string[]): string | null {
  const r = spawnSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return r.error || r.status !== 0 ? null : r.stdout.trim();
}

/** The cache key for this checkout, or why the cache cannot be used. */
export function dmbcCacheKey(root: string): CacheKey {
  const dirty = git(root, ['status', '--porcelain', '--untracked-files=all', '--', ...DMBC_CACHE_INPUTS]);
  if (dirty === null) return { bypass: 'not a git checkout' };
  if (dirty) return { bypass: `uncommitted changes in compiler inputs (${dirty.split('\n')[0].trim()}...)` };
  // A directory entry's id covers its whole subtree; `-d` keeps the listing to one line per input.
  const ids = git(root, ['ls-tree', 'HEAD', '--', ...DMBC_CACHE_INPUTS]);
  const commit = git(root, ['rev-parse', 'HEAD']);
  if (!ids || !commit) return { bypass: 'cannot resolve compiler inputs at HEAD' };
  const key = createHash('sha256')
    .update([`v${CACHE_VERSION}`, process.platform, process.arch, 'release', ids].join('\0'))
    .digest('hex')
    .slice(0, 32);
  return { key, commit };
}

/** A cargo failure that stale shared-target state (not the source) explains; see DmbcTarget in build.ts. */
export const staleCargoArtifactSignature = (output: string): boolean =>
  /error\[E0599\]|error\[E04(32|33)\]|error\[E0425\]|internal compiler error|incremental compilation|failed to (?:load|read) (?:dep-info|fingerprint)/i.test(output);

export function dmbcPairId(dir: string): string {
  const h = createHash('sha256');
  for (const name of ['dmbc', 'dmbd']) h.update(fs.readFileSync(`${dir}/${name}${EXE_SUFFIX}`));
  return h.digest('hex').slice(0, 16);
}

function renameWithRetry(from: string, to: string): void {
  for (let attempt = 0; ; attempt++) {
    try {
      fs.renameSync(from, to);
      return;
    } catch (error) {
      // Windows refuses a rename over a file a reader has open for a moment; the pointer is tiny, so retry briefly.
      if (attempt >= 20) throw error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
    }
  }
}

/**
 * Publish the pair found in `srcDir` as an immutable version and make it current; returns the version id. The directory is
 * assembled under a temporary name and renamed into place (a version either exists whole or not at all), an existing version is
 * never rewritten, and `current` is replaced atomically. Safe against any number of concurrent publishers and running compiles.
 */
export function publishDmbcVersion(srcDir: string, binDir: string = sharedDmbcBinDir()): string {
  const id = dmbcPairId(srcDir);
  const dest = dmbcVersionDir(binDir, id);
  if (!fs.existsSync(`${dest}/dmbc${EXE_SUFFIX}`) || !fs.existsSync(`${dest}/dmbd${EXE_SUFFIX}`)) {
    const tmp = `${binDir}/v/.tmp-${id}-${process.pid}-${Date.now()}`;
    fs.mkdirSync(tmp, { recursive: true });
    for (const name of ['dmbc', 'dmbd']) fs.copyFileSync(`${srcDir}/${name}${EXE_SUFFIX}`, `${tmp}/${name}${EXE_SUFFIX}`);
    try {
      fs.renameSync(tmp, dest);
    } catch (error) {
      // a concurrent publisher of the same bytes won the rename: its version is identical
      fs.rmSync(tmp, { recursive: true, force: true });
      if (!fs.existsSync(`${dest}/dmbc${EXE_SUFFIX}`)) throw error;
    }
  }
  if (readCurrentDmbcVersion(binDir) !== id) {
    const tmpPointer = `${binDir}/current.tmp-${process.pid}-${Date.now()}`;
    fs.writeFileSync(tmpPointer, `${id}\n`);
    renameWithRetry(tmpPointer, `${binDir}/current`);
  }
  unpinDmbcVersion(binDir);
  return id;
}

/**
 * Delete versions nobody needs: keep the current one and the `keep` newest others; a version a running daemon or compile still
 * holds cannot be deleted on Windows and is simply tried again next time. Also drops abandoned temporary directories.
 */
export function pruneDmbcVersions(keep = 3, binDir: string = sharedDmbcBinDir()): number {
  const current = readCurrentDmbcVersion(binDir);
  let removed = 0;
  const vdir = `${binDir}/v`;
  let entries: string[] = [];
  try {
    entries = fs.readdirSync(vdir);
  } catch {
    return 0;
  }
  const mtimeOf = (name: string): number => {
    try {
      return fs.statSync(`${vdir}/${name}`).mtimeMs;
    } catch {
      return 0;
    }
  };
  const dated = entries.map((name) => ({ name, mtime: mtimeOf(name) })).sort((a, b) => b.mtime - a.mtime);
  let kept = 0;
  for (const { name, mtime } of dated) {
    if (name === current) continue;
    const tmp = name.startsWith('.tmp-');
    if (!tmp && kept < keep) {
      kept++;
      continue;
    }
    if (tmp && Date.now() - mtime < 10 * 60_000) continue; // a publisher may still be copying
    try {
      fs.rmSync(`${vdir}/${name}`, { recursive: true, force: true });
      removed++;
    } catch {
      // still running under a daemon; the next publish retries
    }
  }
  return removed;
}

/** Publish a freshly built compiler pair (a cargo `release` dir) as the new shared version. */
export function publishDmbc(builtDir: string): string {
  return publishDmbcVersion(builtDir);
}

/**
 * Make the cached executables the current version. Returns true on a hit. Nothing a running compile uses is touched: the cache
 * entry's pair is published as an immutable version (a no-op when that version already exists) and `current` is switched.
 */
export function restoreDmbc(cache: string, key: string): boolean {
  const dir = path.join(cache, key, 'release');
  if (!fs.existsSync(path.join(dir, 'manifest.json'))) return false;
  if (!['dmbc', 'dmbd'].every((name) => fs.existsSync(path.join(dir, `${name}${EXE_SUFFIX}`)))) return false;
  publishDmbcVersion(dir.split(path.sep).join('/'));
  try {
    const now = new Date();
    fs.utimesSync(path.join(cache, key), now, now);
  } catch {
    // best effort: pruning keeps recently used entries
  }
  return true;
}

export function storeDmbc(cache: string, key: string, commit: string, exe: string, daemon: string): void {
  storeVerdigris(cache, key, commit, [exe, daemon], { kind: 'dmbc', platform: process.platform, arch: process.arch });
}

export { dropVerdigris as dropDmbc };
