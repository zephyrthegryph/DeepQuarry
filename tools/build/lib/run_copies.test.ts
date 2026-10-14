// Run with `bun test tools/build/lib/run_copies.test.ts`.
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pruneStaleRunCopies, runCopyBase } from './run_copies';

let dir = '';
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dq-run-copies-'));
});
afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('run copies', () => {
  test('a slot reused by another process never targets the earlier occupant\'s file', () => {
    const base = path.join(dir, 'deepquarry.test');
    const first = runCopyBase(base, 'run2', 1111);
    const second = runCopyBase(base, 'run2', 2222);
    expect(first).not.toBe(second);
    // The earlier occupant's copy is left behind (its removal failed); the next run copies to a different name, so the leftover cannot make the copy fail.
    fs.writeFileSync(`${first}.dmb`, 'old world');
    fs.writeFileSync(`${base}.dmb`, 'new world');
    fs.copyFileSync(`${base}.dmb`, `${second}.dmb`);
    expect(fs.readFileSync(`${second}.dmb`, 'utf-8')).toBe('new world');
  });

  test('prunes the copies of dead processes only, and reports names removed', () => {
    const base = path.join(dir, 'deepquarry.test');
    for (const [tag, pid] of [['run1', 100], ['run2', 200]] as const) {
      for (const ext of ['dmb', 'rsc', 'dyn.rsc']) fs.writeFileSync(`${runCopyBase(base, tag, pid)}.${ext}`, 'x');
    }
    fs.writeFileSync(`${base}.dmb`, 'the compiled world');
    fs.writeFileSync(path.join(dir, 'deepquarry.test.run3.dmb'), 'legacy name, untouched');
    const warnings: string[] = [];
    const removed = pruneStaleRunCopies(base, (pid) => pid === 200, (m) => warnings.push(m));
    expect(removed.sort()).toEqual(['deepquarry.test.run1.p100.dmb', 'deepquarry.test.run1.p100.dyn.rsc', 'deepquarry.test.run1.p100.rsc']);
    expect(warnings).toEqual([]);
    expect(fs.existsSync(`${runCopyBase(base, 'run2', 200)}.dmb`)).toBe(true);
    expect(fs.existsSync(`${base}.dmb`)).toBe(true);
    expect(fs.existsSync(path.join(dir, 'deepquarry.test.run3.dmb'))).toBe(true);
  });

  test('a missing directory is not an error', () => {
    expect(pruneStaleRunCopies(path.join(dir, 'nope', 'x'), () => false, () => {})).toEqual([]);
  });
});
