/**
 * Shared compile roots: one stable project root per DME variant, so the resident compiler keeps ONE session per variant
 * instead of one per worktree, and a compile in any worktree reuses the session another worktree warmed.
 *
 * A compile root `<roots>/<variant>` holds
 *   - a junction (symlink on POSIX) to each top-level input directory of the worktree being compiled (code, icons, ...),
 *   - a content-compared copy of the worktree's root-level input files (the manifest, *.dmm, DLLs),
 *   - the compiler's own outputs (`<variant>.dmb` and friends), copied back into the worktree after a successful compile.
 * The compiler sees the same relative layout whatever the worktree, so its retained session is keyed by the variant. Everything
 * it records is validated against the files it actually reads (stamps, then content hashes), so a compile in worktree B after one
 * in worktree A rehashes only what differs; the daemon's filesystem watcher never caches a directory behind a link
 * (tools/dmb/crates/dmbc/src/fs_watch.rs), so an edit below a re-pointed link is always seen.
 *
 * Safety rules, because a link into a live worktree is a hazard for any recursive delete:
 *   - nothing here ever deletes recursively; a link is removed with rmdir/unlink, which never touches its target, and a real
 *     directory where a link belongs is an error, not something to clear;
 *   - the links exist only while a compile holds the root (they are removed in `finally`), so an idle root holds no link;
 *   - one compile at a time per root (a machine slot), because the links name exactly one worktree.
 * `DQ_SHARED_ROOT=0` turns the whole mechanism off (the compiler then runs on the worktree itself, as before).
 */
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { withSlot } from './machine_slots';

/** Top-level directories that are never compiler inputs (build tooling, docs, other languages, build output). */
const NOT_INPUTS = new Set(['node_modules', 'data', 'tools', 'bin', 'doc', 'guides', 'SQL', 'verdigris', 'dist']);
/** Root-level files that are compiler output or noise, never copied into the root and never copied back over by mistake. */
/** `*.lk` are lock files held by a running DreamDaemon/DreamMaker (`deepquarry.rsc.lk`): never copied, never deleted. */
const OUTPUT_FILE = /\.(dmb|rsc|lk|log|stackdump|compiler|tmp)$|-pair\.json$|\.dmb\./i;

export function sharedRootEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return (env.DQ_SHARED_ROOT ?? '1') !== '0';
}

export function compileRootsDir(env: NodeJS.ProcessEnv = process.env): string {
  if (env.DQ_COMPILE_ROOTS) return path.resolve(env.DQ_COMPILE_ROOTS);
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/dmb-roots';
  return path.join(os.homedir(), '.cache', 'dq', 'dmb-roots');
}

/** The variant key of a manifest: its file name without extension (`deepquarry`, `deepquarry.test`, `deepquarry.bench`). */
export function variantKey(dme: string): string {
  return path.basename(dme).replace(/\.dme$/i, '').replace(/[^A-Za-z0-9._-]/g, '_');
}

/**
 * The compile root of a manifest: the part of its file name before the first dot, so `deepquarry.dme`, `deepquarry.test.dme` and
 * `deepquarry.bench.dme` share one root (one project directory, hence one resident session). The define sets and the manifest file
 * differ per build; the session keeps each variant's own state and shares everything that does not depend on the defines.
 */
export function rootKey(dme: string): string {
  return variantKey(dme).split('.')[0] || variantKey(dme);
}

function normalizeTarget(target: string): string {
  let text = target.replace(/^\\\\\?\\/, '');
  text = path.resolve(text);
  return process.platform === 'win32' ? text.toLowerCase() : text;
}

function isLink(file: string): boolean {
  try { return fs.lstatSync(file).isSymbolicLink(); } catch { return false; }
}
function exists(file: string): boolean {
  try { fs.lstatSync(file); return true; } catch { return false; }
}

/** Remove a link without touching its target. Throws for anything that is not a link. */
export function removeLink(file: string): void {
  if (!isLink(file)) throw new Error(`Compile root entry ${file} is not a link; refusing to remove it.`);
  try { fs.rmdirSync(file); }
  catch { fs.unlinkSync(file); }
}

function pointLink(file: string, target: string): void {
  if (exists(file)) {
    if (!isLink(file)) throw new Error(`Compile root entry ${file} is a real file or directory where a link belongs; remove it by hand.`);
    let current: string | undefined;
    try { current = fs.readlinkSync(file); } catch { /* unreadable: replace it */ }
    if (current !== undefined && normalizeTarget(current) === normalizeTarget(target)) return;
    removeLink(file);
  }
  fs.symlinkSync(target, file, process.platform === 'win32' ? 'junction' : 'dir');
}

function sameContent(a: string, b: string): boolean {
  let sa: fs.Stats, sb: fs.Stats;
  try { sa = fs.statSync(a); sb = fs.statSync(b); } catch { return false; }
  if (sa.size !== sb.size) return false;
  const hash = (file: string) => createHash('sha1').update(fs.readFileSync(file)).digest('hex');
  return hash(a) === hash(b);
}

const BUSY_CODES = new Set(['EBUSY', 'EPERM', 'EACCES']);
/**
 * Copy `from` to `to` through a temporary file, retrying briefly when the file is busy (a scanner or a running world holds it;
 * EBUSY on Windows). After the attempts it fails with a message that names the file and says what to do. `attempts`/`delayMs`
 * are parameters so tests can use fakes.
 */
export function copyFileRetrying(from: string, to: string, attempts = 6, delayMs = 500, copy: (a: string, b: string) => void = fs.copyFileSync, rename: (a: string, b: string) => void = fs.renameSync): void {
  const temporary = `${to}.tmp-${process.pid}`;
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      copy(from, temporary);
      // A copy of a read-only store link keeps the attribute on Windows; the worktree's file must stay an ordinary writable one.
      try { fs.chmodSync(temporary, 0o666); } catch { /* the injected copy in a test made no file */ }
      rename(temporary, to);
      return;
    } catch (error) {
      last = error;
      try { fs.unlinkSync(temporary); } catch { /* none */ }
      if (!BUSY_CODES.has((error as NodeJS.ErrnoException).code ?? '')) throw error;
      if (i < attempts - 1) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, delayMs);
    }
  }
  throw new Error(`Compile root: ${to} stayed busy (${(last as NodeJS.ErrnoException).code}) after ${attempts} attempts; a running DreamDaemon/DreamMaker or a scanner holds it. Stop that process and rerun; never delete lock files by hand.`);
}

/**
 * Marker file in a compile root: the compiler installs its outputs there as hard links to the immutable pair-store files instead
 * of copies (tools/dmb/crates/dmbc/src/publish_install.rs `LINK_MARKER`). Only the root has it; the worktree's own outputs stay
 * independent writable files, because a tool may overwrite those in place. `DMB_INSTALL_LINK=0` leaves the marker out.
 */
export const LINK_MARKER = '.dmb-link-outputs';
/**
 * A root whose outputs may be links lives in its own directory (`<key>-l1`), never in the plain `<key>` root: a compiler from before
 * linking cannot replace a read-only link ("Access is denied"), and lanes on an older compiler still compile in the plain root.
 * `DMB_INSTALL_LINK=0` selects the plain root again.
 */
export const LINK_ROOT_SUFFIX = '-l1';
export function linkOutputsEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return (env.DMB_INSTALL_LINK ?? '1') !== '0';
}

export type SyncReport = { linked: string[]; unlinked: string[]; copied: string[]; removed: string[] };

/**
 * Make `root` a view of `worktree`: re-point the input links and bring the root-level files to the worktree's content (a
 * file whose bytes already match is left untouched, so its stamp does not churn). Safe to call repeatedly.
 */
export function syncCompileRoot(worktree: string, root: string, manifest: string): SyncReport {
  const report: SyncReport = { linked: [], unlinked: [], copied: [], removed: [] };
  fs.mkdirSync(root, { recursive: true });
  const marker = path.join(root, LINK_MARKER);
  if (!linkOutputsEnabled()) fs.rmSync(marker, { force: true });
  else if (path.basename(root).endsWith(LINK_ROOT_SUFFIX) && !fs.existsSync(marker)) fs.writeFileSync(marker, 'conventional outputs here are hard links to the pair store\n');
  const wanted = new Set<string>();
  for (const entry of fs.readdirSync(worktree, { withFileTypes: true })) {
    const name = entry.name;
    if (name.startsWith('.')) continue;
    const source = path.join(worktree, name);
    const dest = path.join(root, name);
    // Worktree-level links (a junction to a shared node_modules, say) count as the directory they name.
    const stat = fs.statSync(source, { throwIfNoEntry: false });
    if (!stat) continue;
    if (stat.isDirectory()) {
      if (NOT_INPUTS.has(name)) continue;
      wanted.add(name);
      const before = exists(dest) ? (() => { try { return fs.readlinkSync(dest); } catch { return undefined; } })() : undefined;
      pointLink(dest, path.resolve(source));
      if (before === undefined || normalizeTarget(before) !== normalizeTarget(source)) report.linked.push(name);
    } else if (stat.isFile() && !OUTPUT_FILE.test(name)) {
      wanted.add(name);
      if (!sameContent(source, dest)) {
        copyFileRetrying(source, dest);
        report.copied.push(name);
      }
    }
  }
  // Entries of an earlier worktree that this one lacks: stale links go; stale copies go; outputs and dotfiles stay.
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const name = entry.name;
    if (wanted.has(name) || name.startsWith('.')) continue;
    const dest = path.join(root, name);
    if (isLink(dest)) { removeLink(dest); report.unlinked.push(name); }
    else if (entry.isFile() && !OUTPUT_FILE.test(name) && name !== path.basename(manifest)) { fs.unlinkSync(dest); report.removed.push(name); }
  }
  return report;
}

/** Remove every link under `root` (never a real entry). Called when a compile releases the root. */
export function releaseCompileRoot(root: string): string[] {
  const removed: string[] = [];
  let entries: fs.Dirent[] = [];
  try { entries = fs.readdirSync(root, { withFileTypes: true }); } catch { return removed; }
  for (const entry of entries) {
    const dest = path.join(root, entry.name);
    if (!isLink(dest)) continue;
    try { removeLink(dest); removed.push(entry.name); } catch { /* left for the next sync, which re-points or removes it */ }
  }
  return removed;
}

/**
 * Output files a compile leaves in the root, copied back so the worktree's conventional files stay current. When the pair
 * receipt is byte-identical to the worktree's and both files exist, the worktree already holds this pair and nothing is copied.
 */
function sizeOf(file: string): number | undefined {
  try { return fs.statSync(file).size; } catch { return undefined; }
}
/** Both pair receipts parse and name the same resource archive (size and hash). */
function sameResourceIdentity(a: string, b: string): boolean {
  try {
    const left = JSON.parse(fs.readFileSync(a, 'utf8'));
    const right = JSON.parse(fs.readFileSync(b, 'utf8'));
    return left.rsc_bytes !== undefined && left.rsc_hash !== undefined
      && String(left.rsc_bytes) === String(right.rsc_bytes) && String(left.rsc_hash) === String(right.rsc_hash);
  } catch { return false; }
}
export function copyBackOutputs(root: string, worktree: string, stem: string): string[] {
  const receipt = `${stem}.dmb-pair.json`;
  try {
    if (fs.readFileSync(path.join(root, receipt), 'utf8') === fs.readFileSync(path.join(worktree, receipt), 'utf8')
      && exists(path.join(worktree, `${stem}.dmb`)) && exists(path.join(worktree, `${stem}.rsc`))) return [];
  } catch { /* a receipt is missing on one side: copy */ }
  const copied: string[] = [];
  // The archive is identified by size and hash in the receipt: when the worktree's receipt names the same one and its file has
  // that size, the 200+ MB copy is skipped (an edit that changes the program leaves the resources alone).
  const sameArchive = sameResourceIdentity(path.join(root, receipt), path.join(worktree, receipt))
    && sizeOf(path.join(worktree, `${stem}.rsc`)) === sizeOf(path.join(root, `${stem}.rsc`));
  for (const suffix of ['.dmb', '.rsc', '.dmb-pair.json']) {
    const from = path.join(root, `${stem}${suffix}`);
    const to = path.join(worktree, `${stem}${suffix}`);
    if (!exists(from)) continue;
    if (suffix === '.rsc' && sameArchive) continue;
    copyFileRetrying(from, to);
    copied.push(path.basename(to));
  }
  return copied;
}

export type SharedRootRun = { root: string; relativeManifest: string };

/**
 * Run `fn` with a compile root that views `worktree`, holding the root's machine slot for the duration. Returns undefined when
 * sharing does not apply (disabled, or the manifest is not a root-level file of `worktree`); the caller then compiles in place.
 * On success of `fn` (`succeeded`), the outputs are copied back into the worktree.
 */
export async function withSharedCompileRoot<T>(
  worktree: string,
  dme: string,
  succeeded: (result: T) => boolean,
  fn: (run: SharedRootRun) => Promise<T>,
  log: (message: string) => void = () => {},
  env: NodeJS.ProcessEnv = process.env,
): Promise<{ result: T } | undefined> {
  if (!sharedRootEnabled(env)) return undefined;
  const manifest = path.resolve(dme);
  const base = path.resolve(worktree);
  if (path.dirname(manifest).toLowerCase() !== base.toLowerCase() || !/\.dme$/i.test(manifest) || !fs.existsSync(manifest)) return undefined;
  const key = rootKey(manifest) + (linkOutputsEnabled(env) ? LINK_ROOT_SUFFIX : '');
  const root = path.join(compileRootsDir(env), key);
  const stem = path.basename(manifest).replace(/\.dme$/i, '');
  return await withSlot(`dmb_root_${key}`, `compile root ${key} <- ${base}`, async () => {
    const started = Date.now();
    const report = syncCompileRoot(base, root, manifest);
    log(`compile root ${root}: viewing ${base} (links ${report.linked.length} changed, files ${report.copied.length} copied, ${report.removed.length + report.unlinked.length} stale removed, ${Date.now() - started} ms)`);
    try {
      const result = await fn({ root, relativeManifest: path.basename(manifest) });
      if (succeeded(result)) {
        const copied = copyBackOutputs(root, base, stem);
        if (copied.length) log(`compile root ${key}: copied ${copied.join(', ')} back to ${base}`);
      }
      return { result };
    } finally {
      releaseCompileRoot(root);
    }
  }, log);
}
