// Content-addressed cache of built Verdigris libraries, shared by every
// checkout and worktree on the machine. The key is the git tree/blob ids of
// every input the library (and its generated ABI) is built from, plus the
// target triple, profile and RUSTFLAGS. A checkout whose inputs differ from
// HEAD (edited, staged or untracked) bypasses the cache. The DreamDaemon ABI
// check (byond.ts checkVerdigrisAbi) stays as the safety net.
//
// Layout: <cache>/<key>/<profile>/{verdigris.dll, verdigris.pdb?, *.provenance.json?, manifest.json}
// Env: DQ_VERDIGRIS_CACHE=<dir> overrides the location; DQ_VERDIGRIS_CACHE=off disables it.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CACHE_VERSION = 1;
const PROFILE = 'release';
const KEEP_NEWEST = 10;
const KEEP_DAYS = 14;

// Everything verdigris_provenance.ts rustInputs() hashes, as git paths.
export const VERDIGRIS_CACHE_INPUTS = [
  'verdigris',
  'code/__defines/verdigris/_bindings.dm',
  'code/__defines/verdigris/_bindings_types.dm',
  'code/__defines/verdigris/_component_schemas.dm',
  'tools/build/lib/verdigris_bindings.ts',
  'tools/generated_station/southern_cross_reference.json',
];

export function verdigrisCacheDir(): string | null {
  const env = process.env.DQ_VERDIGRIS_CACHE;
  if (env === 'off' || env === '0') return null;
  if (env) return path.resolve(env);
  if (process.platform === 'win32' && fs.existsSync('D:/')) return 'D:/dq-cache/verdigris';
  return path.join(os.homedir(), '.cache', 'dq', 'verdigris');
}

function git(root: string, args: string[]): string | null {
  const r = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  return r.error || r.status !== 0 ? null : r.stdout.trim();
}

export type CacheKey = { key: string; commit: string } | { bypass: string };

/** The cache key for this checkout, or why the cache cannot be used. */
export function verdigrisCacheKey(root: string, target: string, rustflags: string, extra = ''): CacheKey {
  const dirty = git(root, ['status', '--porcelain', '--untracked-files=all', '--', ...VERDIGRIS_CACHE_INPUTS]);
  if (dirty === null) return { bypass: 'not a git checkout' };
  if (dirty) return { bypass: `uncommitted changes in verdigris inputs (${dirty.split('\n')[0].trim()}...)` };
  // ls-tree lists the tree/blob id of each input that exists (some are optional).
  const ids = git(root, ['ls-tree', 'HEAD', '--', ...VERDIGRIS_CACHE_INPUTS]);
  const commit = git(root, ['rev-parse', 'HEAD']);
  if (!ids || !commit) return { bypass: 'cannot resolve verdigris inputs at HEAD' };
  const key = createHash('sha256')
    .update([`v${CACHE_VERSION}`, process.platform, target, PROFILE, rustflags, extra, ids].join('\0'))
    .digest('hex')
    .slice(0, 32);
  return { key, commit };
}

function entryDir(cache: string, key: string): string {
  return path.join(cache, key, PROFILE);
}

/** Copy a cached library into the checkout. Returns true on a hit. */
export function restoreVerdigris(cache: string, key: string, lib: string, sidecars: string[]): boolean {
  const dir = entryDir(cache, key);
  const cached = path.join(dir, path.basename(lib));
  if (!fs.existsSync(path.join(dir, 'manifest.json')) || !fs.existsSync(cached)) return false;
  const same =
    fs.existsSync(lib) &&
    fs.statSync(lib).size === fs.statSync(cached).size &&
    fs.readFileSync(lib).equals(fs.readFileSync(cached));
  if (!same) {
    const tmp = `${lib}.cache-tmp-${process.pid}`;
    fs.copyFileSync(cached, tmp);
    fs.rmSync(lib, { force: true });
    fs.renameSync(tmp, lib);
  }
  for (const sidecar of sidecars) {
    const from = path.join(dir, path.basename(sidecar));
    if (fs.existsSync(from)) fs.copyFileSync(from, sidecar);
  }
  // Touch the key dir so pruning keeps recently used entries.
  const now = new Date();
  try {
    fs.utimesSync(path.join(cache, key), now, now);
  } catch {
    // best effort
  }
  return true;
}

export function dropVerdigris(cache: string, key: string): void {
  fs.rmSync(path.join(cache, key), { recursive: true, force: true });
}

/** Store a freshly built library atomically (temp dir + rename), then prune. */
export function storeVerdigris(
  cache: string,
  key: string,
  commit: string,
  files: string[],
  manifest: Record<string, unknown>,
): void {
  const final = path.join(cache, key);
  if (fs.existsSync(path.join(entryDir(cache, key), 'manifest.json'))) return;
  fs.mkdirSync(cache, { recursive: true });
  const tmp = path.join(cache, `.tmp-${key}-${process.pid}-${Date.now()}`);
  const tmpEntry = path.join(tmp, PROFILE);
  fs.mkdirSync(tmpEntry, { recursive: true });
  for (const file of files) if (fs.existsSync(file)) fs.copyFileSync(file, path.join(tmpEntry, path.basename(file)));
  fs.writeFileSync(
    path.join(tmpEntry, 'manifest.json'),
    `${JSON.stringify({ version: CACHE_VERSION, key, commit, profile: PROFILE, builtAt: new Date().toISOString(), ...manifest }, null, 2)}\n`,
  );
  try {
    fs.rmSync(final, { recursive: true, force: true });
    fs.renameSync(tmp, final);
  } catch {
    // Another build stored the same key concurrently; theirs is equivalent.
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  pruneVerdigrisCache(cache);
}

/** Keep the newest KEEP_NEWEST entries and anything used in the last KEEP_DAYS. */
export function pruneVerdigrisCache(cache: string): void {
  const cutoff = Date.now() - KEEP_DAYS * 86400_000;
  const entries = fs
    .readdirSync(cache, { withFileTypes: true })
    .map((e) => path.join(cache, e.name))
    .map((p) => ({ p, base: path.basename(p), mtime: fs.statSync(p).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
  let kept = 0;
  for (const e of entries) {
    if (e.base.startsWith('.tmp-')) {
      // Leftover from a killed build.
      if (e.mtime < Date.now() - 3600_000) fs.rmSync(e.p, { recursive: true, force: true });
      continue;
    }
    if (kept < KEEP_NEWEST || e.mtime >= cutoff) kept++;
    else fs.rmSync(e.p, { recursive: true, force: true });
  }
}
