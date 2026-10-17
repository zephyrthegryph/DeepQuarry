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
const OUTPUT_FILE = /\.(dmb|rsc|log|stackdump|compiler|tmp)$|-pair\.json$|\.dmb\./i;

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

export type SyncReport = { linked: string[]; unlinked: string[]; copied: string[]; removed: string[] };

/**
 * Make `root` a view of `worktree`: re-point the input links and bring the root-level files to the worktree's content (a
 * file whose bytes already match is left untouched, so its stamp does not churn). Safe to call repeatedly.
 */
export function syncCompileRoot(worktree: string, root: string, manifest: string): SyncReport {
  const report: SyncReport = { linked: [], unlinked: [], copied: [], removed: [] };
  fs.mkdirSync(root, { recursive: true });
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
        const temporary = `${dest}.tmp-${process.pid}`;
        fs.copyFileSync(source, temporary);
        fs.renameSync(temporary, dest);
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
export function copyBackOutputs(root: string, worktree: string, stem: string): string[] {
  const receipt = `${stem}.dmb-pair.json`;
  try {
    if (fs.readFileSync(path.join(root, receipt), 'utf8') === fs.readFileSync(path.join(worktree, receipt), 'utf8')
      && exists(path.join(worktree, `${stem}.dmb`)) && exists(path.join(worktree, `${stem}.rsc`))) return [];
  } catch { /* a receipt is missing on one side: copy */ }
  const copied: string[] = [];
  for (const suffix of ['.dmb', '.rsc', '.dmb-pair.json']) {
    const from = path.join(root, `${stem}${suffix}`);
    const to = path.join(worktree, `${stem}${suffix}`);
    if (!exists(from)) continue;
    const temporary = `${to}.tmp-${process.pid}`;
    fs.copyFileSync(from, temporary);
    fs.renameSync(temporary, to);
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
  const key = variantKey(manifest);
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
