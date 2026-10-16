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

/**
 * Copy the cached executables into place. Returns true on a hit. A running daemon holds its executable open
 * (Windows refuses to delete it but allows a rename), so a differing file is moved aside, never overwritten.
 */
export function restoreDmbc(cache: string, key: string, exe: string, daemon: string): boolean {
  const dir = path.join(cache, key, 'release');
  if (!fs.existsSync(path.join(dir, 'manifest.json'))) return false;
  const files = [exe, daemon];
  if (!files.every((file) => fs.existsSync(path.join(dir, path.basename(file))))) return false;
  for (const file of files) {
    const cached = path.join(dir, path.basename(file));
    const same =
      fs.existsSync(file) &&
      fs.statSync(file).size === fs.statSync(cached).size &&
      fs.readFileSync(file).equals(fs.readFileSync(cached));
    if (same) continue;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.cache-tmp-${process.pid}`;
    fs.copyFileSync(cached, tmp);
    try {
      fs.rmSync(file, { force: true });
    } catch {
      fs.renameSync(file, `${file}.old-${Date.now()}`);
    }
    fs.renameSync(tmp, file);
  }
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
