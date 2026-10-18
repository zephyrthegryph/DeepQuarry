import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readCurrentDmbcVersion, readNextDmbcVersion, stageDmbcVersion } from './dmbc_cache';
import { acquirePrewarmLock, enoughMemoryToPrewarm, lastVariant, planPrewarm, warmAndPromote } from './dmbc_prewarm';
import { spawnSync } from 'node:child_process';
import { publishDmbcVersion } from './dmbc_cache';

const SUFFIX = process.platform === 'win32' ? '.exe' : '';
let tmp: string;
let bin: string;
let state: string;

function pair(name: string, bytes: string): string {
  const dir = path.join(tmp, name).split(path.sep).join('/');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(`${dir}/dmbc${SUFFIX}`, `dmbc:${bytes}`);
  fs.writeFileSync(`${dir}/dmbd${SUFFIX}`, `dmbd:${bytes}`);
  return dir;
}
const stat = (variant: string, atMs: number, error: string | null = null) =>
  `${JSON.stringify({ at_ms: atMs, variant, error })}\n`;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dmbc-prewarm-'));
  bin = path.join(tmp, 'bin').split(path.sep).join('/');
  state = path.join(tmp, 'state').split(path.sep).join('/');
  fs.mkdirSync(bin, { recursive: true });
  fs.mkdirSync(state, { recursive: true });
});
afterEach(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe('which variant to prewarm', () => {
  test('the last successful compile decides, and only when it was recent', () => {
    const now = Date.now();
    fs.writeFileSync(`${state}/compile-stats.jsonl`, stat('deepquarry.dme', now - 60_000) + stat('deepquarry.test.dme', now - 30_000) + stat('deepquarry.bench.dme', now - 10_000) + stat('deepquarry.dme', now - 5_000, 'boom'));
    expect(lastVariant(state, now)).toBe('test');
    expect(lastVariant(state, now + 7 * 3600 * 1000)).toBeNull();
    fs.writeFileSync(`${state}/compile-stats.jsonl`, stat('deepquarry.dme', now - 1000));
    expect(lastVariant(state, now)).toBe('production');
    expect(lastVariant(`${state}/missing`, now)).toBeNull();
  });
});

describe('the prewarm lock and the decision', () => {
  test('one prewarm at a time; a stale lock is replaced', () => {
    const first = acquirePrewarmLock(bin);
    expect(first).not.toBeNull();
    expect(acquirePrewarmLock(bin)).toBeNull();
    first?.();
    const again = acquirePrewarmLock(bin);
    expect(again).not.toBeNull();
    expect(acquirePrewarmLock(bin, Date.now() + 31 * 60_000)).not.toBeNull();
    again?.();
  });

  test('memory, switch and history gate it', () => {
    expect(enoughMemoryToPrewarm(30e9, 20e9)).toBe(true);
    expect(enoughMemoryToPrewarm(10e9, 20e9)).toBe(false);
    expect('skipped' in planPrewarm(bin, { DQ_DMBC_PREWARM: '0' })).toBe(true);
    const nothing = planPrewarm(bin, { DMB_DAEMON_DIR: state });
    expect(nothing).toEqual({ skipped: 'no compile in the last 6 hours' });
  });
});

describe('candidate, warm, promote', () => {
  function repo(): { root: string; first: string; second: string } {
    const root = path.join(tmp, 'repo').split(path.sep).join('/');
    fs.mkdirSync(root, { recursive: true });
    const git = (...args: string[]) => {
      const r = spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd: root, encoding: 'utf8' });
      if (r.status !== 0) throw new Error(r.stderr);
      return r.stdout.trim();
    };
    git('init', '-q');
    fs.writeFileSync(`${root}/a`, '1');
    git('add', '-A');
    git('commit', '-qm', 'first');
    const first = git('rev-parse', 'HEAD');
    fs.writeFileSync(`${root}/a`, '2');
    git('commit', '-qam', 'second');
    return { root, first, second: git('rev-parse', 'HEAD') };
  }

  test('current stays on the old version while the candidate warms, then moves', async () => {
    const { root, first, second } = repo();
    const old = publishDmbcVersion(pair('old', 'old'), bin, { root, commit: first });
    const staged = stageDmbcVersion(pair('new', 'new'), bin, { root, commit: second });
    expect(staged).not.toBeNull();
    expect(readCurrentDmbcVersion(bin)).toBe(old);
    expect(readNextDmbcVersion(bin)).toBe(staged);
    const release = acquirePrewarmLock(bin);
    let during = '';
    const outcome = await warmAndPromote({ variant: 'test', release: release ?? (() => {}) }, bin, staged as string, async () => {
      during = readCurrentDmbcVersion(bin) ?? '';
      return 0;
    });
    expect(during).toBe(old);
    expect(outcome.code).toBe(0);
    expect(readCurrentDmbcVersion(bin)).toBe(staged);
    expect(readNextDmbcVersion(bin)).toBeNull();
    expect(fs.readFileSync(`${bin}/current.commit`, 'utf8').trim()).toBe(second);
    expect(acquirePrewarmLock(bin)).not.toBeNull();
  });

  test('a failed warm-up still promotes: the cost is only the cold compile it meant to save', async () => {
    const { root, first, second } = repo();
    publishDmbcVersion(pair('old', 'old'), bin, { root, commit: first });
    const staged = stageDmbcVersion(pair('new', 'new'), bin, { root, commit: second }) as string;
    await warmAndPromote({ variant: 'production', release: () => {} }, bin, staged, async () => {
      throw new Error('compile failed');
    });
    expect(readCurrentDmbcVersion(bin)).toBe(staged);
  });

  test('nothing is staged for an older tree or for the version that is already current', () => {
    const { root, first, second } = repo();
    const current = publishDmbcVersion(pair('now', 'now'), bin, { root, commit: second });
    expect(stageDmbcVersion(pair('older', 'older'), bin, { root, commit: first })).toBeNull();
    expect(stageDmbcVersion(pair('now2', 'now'), bin, { root, commit: second })).toBeNull();
    expect(readCurrentDmbcVersion(bin)).toBe(current);
    expect(readNextDmbcVersion(bin)).toBeNull();
  });
});
