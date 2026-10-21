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
 * One latest compiler for everyone. The shared binary is immutable per version: `<bin>/v/<id>/{dmbc,dmbd}[.exe]`, `<id>` the
 * content hash of the pair, and `<bin>/current` names the version EVERY checkout runs, at any tree, resolved at the start of each
 * compile (a fix is picked up by the next compile anywhere). `current` only moves forward along master's history: a publish
 * advances it when its commit descends from (or is) the commit `<bin>/current.commit` recorded, so a lane that restores an older
 * tree's compiler from the cache can no longer move every other lane back to it, and a checkout behind `current` builds nothing.
 * The one exception is compiler development: a checkout whose compiler sources are dirty builds into its own private target
 * (`devCompilerDir`), runs that build, and never publishes, never moves `current` and never touches the shared daemon (the
 * compiler puts a build outside `<bin>/v` in a private daemon namespace by itself).
 * Publishing writes a new version directory and never touches a version a compile may be running, so a publish mid-gate cannot
 * change the executable under it ("Native executable changed during compilation"). A bin dir with no `current` is the
 * pre-versioning layout `<bin>/dmbc[.exe]`, still honoured.
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

/** The version the next compile runs. Resolved on every call: a process never keeps an older compiler than `current`. */
export function pinnedDmbcVersion(binDir: string = sharedDmbcBinDir()): string | null {
  return readCurrentDmbcVersion(binDir);
}

/** Kept for callers that republished and wanted their own result: resolution is no longer cached, so nothing to drop. */
export function unpinDmbcVersion(_binDir: string = sharedDmbcBinDir()): void {}

/** Private build directory of a checkout that develops the compiler (never shared, never published). */
export function devCompilerDir(root: string = process.env.DQ_BUILD_ROOT ?? process.cwd()): string {
  const normal = path.resolve(root).split(path.sep).join('/').toLowerCase();
  const base = process.platform === 'win32' && fs.existsSync('E:/dq-cache') ? 'E:/dq-cache' : path.join(os.homedir(), '.cache', 'dq');
  return `${base.split(path.sep).join('/')}/dmb-dev/${createHash('sha256').update(normal).digest('hex').slice(0, 16)}`;
}

const dirtyMemo = new Map<string, boolean>();
/** True when the checkout's compiler sources differ from HEAD (compiler development). Decided once per process. */
export function compilerSourcesDirty(root: string = process.env.DQ_BUILD_ROOT ?? process.cwd()): boolean {
  if (!dirtyMemo.has(root)) {
    const key = dmbcCacheKey(root);
    dirtyMemo.set(root, 'bypass' in key && key.bypass.startsWith('uncommitted'));
  }
  return dirtyMemo.get(root) ?? false;
}

export function sharedDmbcExe(name: 'dmbc' | 'dmbd' = 'dmbc'): string {
  if (compilerSourcesDirty()) {
    const own = `${devCompilerDir()}/release/${name}${EXE_SUFFIX}`;
    if (fs.existsSync(own)) return own;
  }
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

function writePointer(file: string, text: string): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmpPointer = `${file}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmpPointer, `${text}\n`);
  renameWithRetry(tmpPointer, file);
}

/** The ref `current` must stay on: master as the shared remote has it. `DQ_DMBC_MASTER_REF` overrides it (tests). */
export function dmbcMasterRef(): string {
  return process.env.DQ_DMBC_MASTER_REF || 'origin/master';
}

function revParse(root: string, ref: string): string | null {
  const out = git(root, ['rev-parse', '--verify', '-q', `${ref}^{commit}`]);
  return out && /^[0-9a-f]{40}$/.test(out) ? out : null;
}

function isAncestor(root: string, ancestor: string, descendant: string): boolean {
  return spawnSync('git', ['merge-base', '--is-ancestor', ancestor, descendant], { cwd: root, encoding: 'utf8' }).status === 0;
}

/**
 * The commit a publish from `commit` records as `current.commit`, or null when it must not publish. `current` only ever names a
 * commit that is in master: a commit in master is recorded as itself; a checkout ahead of master (a lane that merged it) whose
 * compiler sources equal master's tip builds master's compiler, so master's tip is recorded; any other commit (compiler changes
 * not merged yet) is refused, because a pointer off master never advances. A private build for a dirty checkout never gets here.
 * With no master ref to compare against (a repository without the remote), the commit is taken as it is.
 */
export function publishableCommit(root: string, commit: string, masterRef: string = dmbcMasterRef()): string | null {
  const master = revParse(root, masterRef);
  if (!master) return commit;
  if (isAncestor(root, commit, master)) return commit;
  const diff = spawnSync('git', ['diff', '--quiet', commit, master, '--', ...DMBC_CACHE_INPUTS], { cwd: root, encoding: 'utf8' });
  return diff.status === 0 ? master : null;
}

/**
 * Whether `commit` may become the `current` compiler. It must be publishable (see `publishableCommit`), and then:
 * - nothing recorded, or the recorded commit is `commit` itself: yes;
 * - the recorded commit is not an ancestor of master (dead or unmerged): yes when the checkout is at or ahead of master's
 *   compiler sources, so a stuck pointer is replaced by the first such checkout;
 * - otherwise (the recorded commit is on master): only a descendant of it, so a checkout behind `current` never moves it back.
 */
export function mayAdvanceCurrent(root: string, commit: string, binDir: string = sharedDmbcBinDir(), masterRef: string = dmbcMasterRef()): boolean {
  const pub = publishableCommit(root, commit, masterRef);
  if (!pub) {
    console.log(`dmbc: ${commit.slice(0, 10)} is not in ${masterRef} and its compiler sources differ from it; it will not become the current compiler`);
    return false;
  }
  let recorded = '';
  try {
    recorded = fs.readFileSync(`${binDir}/current.commit`, 'utf8').trim();
  } catch {
    return true;
  }
  if (!/^[0-9a-f]{40}$/.test(recorded) || recorded === pub) return true;
  const master = revParse(root, masterRef);
  if (master && !isAncestor(root, recorded, master)) {
    // current names a commit that is on no path of master: it can never advance by ancestry. Replace it from a checkout whose
    // compiler sources are master's (or master's own commit at the tip).
    const same = pub === master || spawnSync('git', ['diff', '--quiet', pub, master, '--', ...DMBC_CACHE_INPUTS], { cwd: root }).status === 0;
    console.log(`dmbc: current.commit ${recorded.slice(0, 10)} is not in ${masterRef}; ${same ? 'replacing it' : 'keeping it (this tree is behind master compiler sources)'}`);
    return same;
  }
  return isAncestor(root, recorded, pub);
}

/** True when `current` was built from `commit` itself: a checkout at that commit has nothing to build or restore. */
export function currentIsCommit(commit: string, binDir: string = sharedDmbcBinDir()): boolean {
  try {
    return fs.readFileSync(`${binDir}/current.commit`, 'utf8').trim() === commit && readCurrentDmbcVersion(binDir) !== null;
  } catch {
    return false;
  }
}

export type PublishFor = { root: string; commit: string };

/** Install the pair in `srcDir` as the immutable version directory `<bin>/v/<id>` (a no-op when it exists); touches no pointer. */
export function installDmbcVersionDir(srcDir: string, binDir: string): string {
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
  return id;
}

/**
 * Publish the pair found in `srcDir` as an immutable version; returns the version id. The directory is assembled under a
 * temporary name and renamed into place (a version either exists whole or not at all), an existing version is never rewritten,
 * and `current` is replaced atomically. Safe against any number of concurrent publishers and running compiles.
 * With `for_`, `current` (and `current.commit`) move only when the publishing commit descends from the one that set them.
 */
export function publishDmbcVersion(srcDir: string, binDir: string = sharedDmbcBinDir(), for_?: PublishFor): string {
  const id = installDmbcVersionDir(srcDir, binDir);
  if (!for_ || mayAdvanceCurrent(for_.root, for_.commit, binDir)) {
    if (readCurrentDmbcVersion(binDir) !== id) writePointer(`${binDir}/current`, id);
    if (for_) writePointer(`${binDir}/current.commit`, publishableCommit(for_.root, for_.commit) ?? for_.commit);
  }
  return id;
}

/** The candidate version being prewarmed (`<bin>/next`), when it exists. */
export function readNextDmbcVersion(binDir: string = sharedDmbcBinDir()): string | null {
  try {
    const id = fs.readFileSync(`${binDir}/next`, 'utf8').trim();
    if (/^[0-9a-f]{16}$/.test(id) && fs.existsSync(`${dmbcVersionDir(binDir, id)}/dmbc${EXE_SUFFIX}`)) return id;
  } catch {
    // no candidate
  }
  return null;
}

/**
 * Publish the pair as a CANDIDATE instead of the current version: the version directory exists and `<bin>/next` names it, but
 * `current` stays where it is, so every compile keeps using the old daemon (and its warm sessions) while the candidate's daemon
 * builds a session for the tree. `promoteDmbcVersion` then makes it current. Returns the id, or null when `current` may not
 * move to this commit (older tree) or already is this version: there is nothing to stage then.
 */
export function stageDmbcVersion(srcDir: string, binDir: string, for_: PublishFor): string | null {
  const id = dmbcPairId(srcDir);
  if (!mayAdvanceCurrent(for_.root, for_.commit, binDir)) return null;
  const recordedCommit = publishableCommit(for_.root, for_.commit) ?? for_.commit;
  if (readCurrentDmbcVersion(binDir) === id) {
    writePointer(`${binDir}/current.commit`, recordedCommit);
    return null;
  }
  installDmbcVersionDir(srcDir, binDir);
  writePointer(`${binDir}/next`, id);
  writePointer(`${binDir}/next.commit`, recordedCommit);
  return id;
}

/** Make the staged candidate `id` the current version (and its commit current.commit) and clear the candidate pointers. */
export function promoteDmbcVersion(binDir: string, id: string): void {
  let commit = '';
  try {
    commit = fs.readFileSync(`${binDir}/next.commit`, 'utf8').trim();
  } catch {
    // no recorded commit: current.commit keeps its value
  }
  if (readCurrentDmbcVersion(binDir) !== id) writePointer(`${binDir}/current`, id);
  if (commit) writePointer(`${binDir}/current.commit`, commit);
  fs.rmSync(`${binDir}/next`, { force: true });
  fs.rmSync(`${binDir}/next.commit`, { force: true });
}

/**
 * Delete versions nobody needs: keep the current one and the `keep` (default 1: the one just superseded) newest others; a version
 * a running daemon or compile still holds cannot be deleted on Windows and is simply tried again next time. Also drops
 * abandoned temporary directories and the per-key and per-tree pointer directories an earlier layout left.
 */
export function pruneDmbcVersions(keep = 1, binDir: string = sharedDmbcBinDir()): number {
  const current = readCurrentDmbcVersion(binDir);
  let removed = 0;
  for (const legacy of ['by-key', 'by-tree']) fs.rmSync(`${binDir}/${legacy}`, { recursive: true, force: true });
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
export function publishDmbc(builtDir: string, for_?: PublishFor): string {
  return publishDmbcVersion(builtDir, sharedDmbcBinDir(), for_);
}

/**
 * Make the cached executables the current version. Returns true on a hit. Nothing a running compile uses is touched: the cache
 * entry's pair is published as an immutable version (a no-op when that version already exists) and `current` is switched.
 */
/** The cached build for `key` when the entry is complete (and mark it recently used), else null. Publishes nothing. */
export function cachedDmbcDir(cache: string, key: string): string | null {
  const dir = path.join(cache, key, 'release');
  if (!fs.existsSync(path.join(dir, 'manifest.json'))) return null;
  if (!['dmbc', 'dmbd'].every((name) => fs.existsSync(path.join(dir, `${name}${EXE_SUFFIX}`)))) return null;
  try {
    const now = new Date();
    fs.utimesSync(path.join(cache, key), now, now);
  } catch {
    // best effort: pruning keeps recently used entries
  }
  return dir.split(path.sep).join('/');
}

export function restoreDmbc(cache: string, key: string, for_?: PublishFor): boolean {
  const dir = path.join(cache, key, 'release');
  if (!fs.existsSync(path.join(dir, 'manifest.json'))) return false;
  if (!['dmbc', 'dmbd'].every((name) => fs.existsSync(path.join(dir, `${name}${EXE_SUFFIX}`)))) return false;
  publishDmbcVersion(dir.split(path.sep).join('/'), sharedDmbcBinDir(), for_);
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
