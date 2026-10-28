import { afterEach, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { copyBackOutputs, copyFileRetrying, releaseCompileRoot, removeLink, rootKey, rootKeyFor, sharedRootEnabled, syncCompileRoot, variantKey, withSharedCompileRoot } from './compile_root';

const made: string[] = [];
function temp(name: string): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `dq-root-${name}-`));
  made.push(dir);
  return dir;
}
function worktree(name: string, files: Record<string, string>): string {
  const dir = temp(name);
  for (const [file, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
    fs.writeFileSync(path.join(dir, file), text);
  }
  return dir;
}
afterEach(() => {
  // Test cleanup only: the roots hold no link by then (each test releases them), and these are temp directories.
  for (const dir of made.splice(0)) {
    try { for (const entry of fs.readdirSync(dir)) { const p = path.join(dir, entry); if (fs.lstatSync(p).isSymbolicLink()) removeLink(p); } } catch { /* ignore */ }
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('variant keys are the manifest stem and the feature is on by default', () => {
  expect(variantKey('E:/x/deepquarry.dme')).toBe('deepquarry');
  expect(variantKey('E:/x/deepquarry.test.dme')).toBe('deepquarry.test');
  // One compile root per project: the game, test and bench manifests are variants of one session.
  expect(rootKey('E:/x/deepquarry.dme')).toBe('deepquarry');
  expect(rootKey('E:/x/deepquarry.test.dme')).toBe('deepquarry');
  expect(rootKey('E:/x/deepquarry.bench.dme')).toBe('deepquarry');
  // The merge worktree has its own root (its gates patch from the previous batch); every other worktree shares one.
  expect(rootKeyFor('E:/projects/dq-wt/merge-base/deepquarry.test.dme', 'E:/projects/dq-wt/merge-base', {})).toBe('deepquarry-merge');
  // The batch train's worktree (tools/dq_train.sh) shares the merge root: both only ever hold master plus a batch.
  expect(rootKeyFor('E:/projects/dq-wt/train-base/deepquarry.test.dme', 'E:/projects/dq-wt/train-base', {})).toBe('deepquarry-merge');
  expect(rootKeyFor('E:/projects/dq-wt/pool-2/deepquarry.dme', 'E:/projects/dq-wt/pool-2', {})).toBe('deepquarry');
  // The train's precheck workers and its parallel-bisect worktree each have a root of their own.
  expect(rootKeyFor('E:/projects/dq-wt/train-pre1/deepquarry.test.dme', 'E:/projects/dq-wt/train-pre1', {})).toBe('deepquarry-pre1');
  expect(rootKeyFor('E:/projects/dq-wt/train-pre2/deepquarry.test.dme', 'E:/projects/dq-wt/train-pre2/', {})).toBe('deepquarry-pre2');
  expect(rootKeyFor('E:/projects/dq-wt/train-bisect/deepquarry.test.dme', 'E:/projects/dq-wt/train-bisect', {})).toBe('deepquarry-bisect');
  expect(rootKeyFor('E:/projects/dq-wt/train-prefix/deepquarry.dme', 'E:/projects/dq-wt/train-prefix', {})).toBe('deepquarry');
  // The train's gate may borrow the warm root of a precheck worker (DQ_TRAIN_ROOT_KEY); nobody else does, and only known train roots.
  expect(rootKeyFor('E:/projects/dq-wt/train-base/deepquarry.test.dme', 'E:/projects/dq-wt/train-base', { DQ_TRAIN_ROOT_KEY: 'pre2' })).toBe('deepquarry-pre2');
  expect(rootKeyFor('E:/projects/dq-wt/train-base/deepquarry.test.dme', 'E:/projects/dq-wt/train-base', { DQ_TRAIN_ROOT_KEY: '../x' })).toBe('deepquarry-merge');
  expect(rootKeyFor('E:/projects/dq-wt/train-bisect/deepquarry.test.dme', 'E:/projects/dq-wt/train-bisect', { DQ_TRAIN_ROOT_KEY: 'pre1' })).toBe('deepquarry-bisect');
  expect(rootKeyFor('E:/projects/dq-wt/merge-base/deepquarry.test.dme', 'E:/projects/dq-wt/merge-base', { DQ_TRAIN_ROOT_KEY: 'pre1' })).toBe('deepquarry-merge');
  expect(sharedRootEnabled({})).toBe(true);
  expect(sharedRootEnabled({ DQ_SHARED_ROOT: '0' })).toBe(false);
});

test('a root becomes a view of the worktree: input dirs linked, root files copied, tooling and dotfiles left out', () => {
  const wt = worktree('a', { 'deepquarry.dme': '#include "code/a.dm"', 'code/a.dm': 'A', 'icons/gen/x.dmi': 'I', 'tools/t.ts': 'T', 'node_modules/m.js': 'M', '.git': 'gitdir', 'palette.dmm': 'P', 'old.dmb': 'OUT' });
  const root = path.join(temp('root'), 'deepquarry');
  const report = syncCompileRoot(wt, root, path.join(wt, 'deepquarry.dme'));
  expect(report.linked.sort()).toEqual(['code', 'icons']);
  expect(fs.readFileSync(path.join(root, 'code/a.dm'), 'utf8')).toBe('A');
  expect(fs.readFileSync(path.join(root, 'icons/gen/x.dmi'), 'utf8')).toBe('I');
  expect(fs.readFileSync(path.join(root, 'deepquarry.dme'), 'utf8')).toBe('#include "code/a.dm"');
  expect(fs.existsSync(path.join(root, 'palette.dmm'))).toBe(true);
  for (const absent of ['tools', 'node_modules', '.git', 'old.dmb']) expect(fs.existsSync(path.join(root, absent))).toBe(false);
  // Idempotent: nothing changes the second time, and an unchanged file keeps its stamp.
  const stamp = fs.statSync(path.join(root, 'deepquarry.dme')).mtimeMs;
  const again = syncCompileRoot(wt, root, path.join(wt, 'deepquarry.dme'));
  expect(again).toEqual({ linked: [], unlinked: [], copied: [], removed: [] });
  expect(fs.statSync(path.join(root, 'deepquarry.dme')).mtimeMs).toBe(stamp);
  releaseCompileRoot(root);
});

test('re-pointing to another worktree never touches either worktree, and content-equal root files keep their stamp', () => {
  const a = worktree('a', { 'deepquarry.dme': 'dme', 'code/a.dm': 'from A', 'palette.dmm': 'same', 'extra.dmm': 'only A' });
  const b = worktree('b', { 'deepquarry.dme': 'dme', 'code/a.dm': 'from B', 'palette.dmm': 'same' });
  const root = path.join(temp('root'), 'deepquarry');
  syncCompileRoot(a, root, path.join(a, 'deepquarry.dme'));
  const stamp = fs.statSync(path.join(root, 'palette.dmm')).mtimeMs;
  const report = syncCompileRoot(b, root, path.join(b, 'deepquarry.dme'));
  expect(report.linked).toEqual(['code']);
  expect(report.removed).toEqual(['extra.dmm']);
  expect(fs.readFileSync(path.join(root, 'code/a.dm'), 'utf8')).toBe('from B');
  expect(fs.statSync(path.join(root, 'palette.dmm')).mtimeMs).toBe(stamp);
  // Both worktrees are intact, including through a write into the root's view of B.
  expect(fs.readFileSync(path.join(a, 'code/a.dm'), 'utf8')).toBe('from A');
  expect(fs.readFileSync(path.join(b, 'code/a.dm'), 'utf8')).toBe('from B');
  expect(releaseCompileRoot(root)).toEqual(['code']);
  expect(fs.readFileSync(path.join(a, 'code/a.dm'), 'utf8')).toBe('from A');
  expect(fs.readFileSync(path.join(b, 'code/a.dm'), 'utf8')).toBe('from B');
  expect(fs.existsSync(path.join(root, 'code'))).toBe(false);
});

test('a real directory where a link belongs is an error, never cleared', () => {
  const wt = worktree('a', { 'deepquarry.dme': 'dme', 'code/a.dm': 'A' });
  const root = path.join(temp('root'), 'deepquarry');
  fs.mkdirSync(path.join(root, 'code'), { recursive: true });
  fs.writeFileSync(path.join(root, 'code', 'precious.txt'), 'keep');
  expect(() => syncCompileRoot(wt, root, path.join(wt, 'deepquarry.dme'))).toThrow('real file or directory');
  expect(fs.readFileSync(path.join(root, 'code', 'precious.txt'), 'utf8')).toBe('keep');
  expect(() => removeLink(path.join(root, 'code'))).toThrow('not a link');
});

test('outputs are copied back only after success, replacing the worktree files atomically', async () => {
  const wt = worktree('a', { 'deepquarry.dme': 'dme', 'code/a.dm': 'A', 'deepquarry.dmb': 'OLD', 'deepquarry.rsc': 'OLDRSC' });
  const roots = temp('roots');
  const env = { DQ_COMPILE_ROOTS: roots, DQ_SLOTS: '0' } as NodeJS.ProcessEnv;
  const manifest = path.join(wt, 'deepquarry.dme');
  const compile = async (run: { root: string; relativeManifest: string }) => {
    expect(run.relativeManifest).toBe('deepquarry.dme');
    expect(fs.readFileSync(path.join(run.root, 'code/a.dm'), 'utf8')).toBe('A');
    fs.writeFileSync(path.join(run.root, 'deepquarry.dmb'), 'NEW');
    fs.writeFileSync(path.join(run.root, 'deepquarry.rsc'), 'NEWRSC');
    fs.writeFileSync(path.join(run.root, 'deepquarry.dmb-pair.json'), '{"pair":"1"}');
    return { code: 0 };
  };
  const failed = await withSharedCompileRoot(wt, manifest, (r: { code: number }) => r.code === 0, async (run) => { fs.writeFileSync(path.join(run.root, 'deepquarry.dmb'), 'BAD'); return { code: 1 }; }, undefined, env);
  expect(failed?.result.code).toBe(1);
  expect(fs.readFileSync(path.join(wt, 'deepquarry.dmb'), 'utf8')).toBe('OLD');
  const ok = await withSharedCompileRoot(wt, manifest, (r: { code: number }) => r.code === 0, compile, undefined, env);
  expect(ok?.result.code).toBe(0);
  expect(fs.readFileSync(path.join(wt, 'deepquarry.dmb'), 'utf8')).toBe('NEW');
  expect(fs.readFileSync(path.join(wt, 'deepquarry.rsc'), 'utf8')).toBe('NEWRSC');
  expect(fs.readFileSync(path.join(wt, 'deepquarry.dmb-pair.json'), 'utf8')).toBe('{"pair":"1"}');
  // The root holds no link once the compile is over, and the worktree still has its sources.
  expect(fs.readdirSync(path.join(roots, 'deepquarry')).filter((name) => fs.lstatSync(path.join(roots, 'deepquarry', name)).isSymbolicLink())).toEqual([]);
  expect(fs.readFileSync(path.join(wt, 'code/a.dm'), 'utf8')).toBe('A');
  // An identical receipt means nothing is copied the next time.
  expect(copyBackOutputs(path.join(roots, 'deepquarry'), wt, 'deepquarry')).toEqual([]);
});

test('a link is released even when the compile throws, and sharing does not apply off the worktree root or when disabled', async () => {
  const wt = worktree('a', { 'deepquarry.dme': 'dme', 'code/a.dm': 'A', 'sub/other.dme': 'x' });
  const roots = temp('roots');
  const env = { DQ_COMPILE_ROOTS: roots, DQ_SLOTS: '0' } as NodeJS.ProcessEnv;
  await expect(withSharedCompileRoot(wt, path.join(wt, 'deepquarry.dme'), () => true, async () => { throw new Error('boom'); }, undefined, env)).rejects.toThrow('boom');
  expect(fs.existsSync(path.join(roots, 'deepquarry', 'code'))).toBe(false);
  expect(fs.readFileSync(path.join(wt, 'code/a.dm'), 'utf8')).toBe('A');
  expect(await withSharedCompileRoot(wt, path.join(wt, 'sub/other.dme'), () => true, async () => 1, undefined, env)).toBeUndefined();
  expect(await withSharedCompileRoot(wt, path.join(wt, 'deepquarry.dme'), () => true, async () => 1, undefined, { ...env, DQ_SHARED_ROOT: '0' })).toBeUndefined();
});

test('a lock file (*.lk) in the worktree is never copied into the root, and a stale one in the root is never deleted', () => {
  const wt = worktree('lk', { 'deepquarry.dme': 'x', 'deepquarry.rsc.lk': 'held', 'code/a.dm': 'A' });
  const root = temp('lk-root');
  fs.writeFileSync(path.join(root, 'old.rsc.lk'), 'held by a world');
  const report = syncCompileRoot(wt, root, path.join(wt, 'deepquarry.dme'));
  expect(report.copied).toEqual(['deepquarry.dme']);
  expect(fs.existsSync(path.join(root, 'deepquarry.rsc.lk'))).toBe(false);
  expect(fs.existsSync(path.join(root, 'old.rsc.lk'))).toBe(true);
  for (const entry of fs.readdirSync(root)) { const p = path.join(root, entry); if (fs.lstatSync(p).isSymbolicLink()) removeLink(p); }
});

test('a busy file is retried briefly, then fails with a clear message', () => {
  const dir = temp('busy');
  const from = path.join(dir, 'a'); const to = path.join(dir, 'b');
  fs.writeFileSync(from, 'data');
  let calls = 0;
  const flaky = (a: string, b: string) => { if (++calls < 3) throw Object.assign(new Error('busy'), { code: 'EBUSY' }); fs.copyFileSync(a, b); };
  copyFileRetrying(from, to, 5, 1, flaky);
  expect(calls).toBe(3);
  expect(fs.readFileSync(to, 'utf8')).toBe('data');
  const always = () => { throw Object.assign(new Error('busy'), { code: 'EBUSY' }); };
  expect(() => copyFileRetrying(from, path.join(dir, 'c'), 3, 1, always)).toThrow(/stayed busy.*3 attempts.*never delete lock files/);
  const other = () => { throw Object.assign(new Error('nope'), { code: 'ENOENT' }); };
  let n = 0;
  expect(() => copyFileRetrying(from, path.join(dir, 'd'), 3, 1, (a, b) => { n++; other(); })).toThrow('nope');
  expect(n).toBe(1);
});
