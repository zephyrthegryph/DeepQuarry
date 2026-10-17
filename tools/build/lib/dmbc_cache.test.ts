import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  currentIsCommit,
  dmbcVersionDir,
  mayAdvanceCurrent,
  pinnedDmbcVersion,
  pruneDmbcVersions,
  publishDmbcVersion,
  readCurrentDmbcVersion,
  staleCargoArtifactSignature,
  unpinDmbcVersion,
} from './dmbc_cache';

const SUFFIX = process.platform === 'win32' ? '.exe' : '';
let tmp: string;
let bin: string;

function pair(name: string, bytes: string): string {
  const dir = path.join(tmp, name).split(path.sep).join('/');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(`${dir}/dmbc${SUFFIX}`, `dmbc:${bytes}`);
  fs.writeFileSync(`${dir}/dmbd${SUFFIX}`, `dmbd:${bytes}`);
  return dir;
}

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dmbc-cache-'));
  bin = path.join(tmp, 'bin').split(path.sep).join('/');
  fs.mkdirSync(bin, { recursive: true });
});

afterEach(() => {
  unpinDmbcVersion(bin);
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe('immutable shared compiler versions', () => {
  test('a publication never rewrites a version a compile may be running', () => {
    const v1 = publishDmbcVersion(pair('built1', 'one'), bin);
    expect(readCurrentDmbcVersion(bin)).toBe(v1);
    const exe1 = `${dmbcVersionDir(bin, v1)}/dmbc${SUFFIX}`;
    const before = fs.readFileSync(exe1, 'utf8');
    const stat1 = fs.statSync(exe1);
    const v2 = publishDmbcVersion(pair('built2', 'two'), bin);
    expect(v2).not.toBe(v1);
    expect(readCurrentDmbcVersion(bin)).toBe(v2);
    expect(fs.readFileSync(exe1, 'utf8')).toBe(before);
    expect(fs.statSync(exe1).mtimeMs).toBe(stat1.mtimeMs);
  });

  test('the next compile runs the latest version: nothing is pinned for the life of a process', () => {
    const v1 = publishDmbcVersion(pair('built1', 'one'), bin);
    expect(pinnedDmbcVersion(bin)).toBe(v1);
    const v2 = publishDmbcVersion(pair('built2', 'two'), bin);
    expect(pinnedDmbcVersion(bin)).toBe(v2);
  });

  test('the same bytes publish to the same version and republishing them is a no-op', () => {
    const a = publishDmbcVersion(pair('a', 'same'), bin);
    const b = publishDmbcVersion(pair('b', 'same'), bin);
    expect(b).toBe(a);
    expect(fs.readdirSync(`${bin}/v`)).toEqual([a]);
  });

  test('a half-written version is never current and a missing pointer reads as the legacy layout', () => {
    expect(readCurrentDmbcVersion(bin)).toBeNull();
    fs.writeFileSync(`${bin}/current`, '0123456789abcdef\n');
    expect(readCurrentDmbcVersion(bin)).toBeNull();
  });

  test('pruning keeps the current version and the newest few, and removes stale temporary directories', () => {
    const ids: string[] = [];
    for (let i = 0; i < 6; i++) {
      ids.push(publishDmbcVersion(pair(`b${i}`, `v${i}`), bin));
      const t = new Date(Date.now() - (10 - i) * 60_000);
      fs.utimesSync(dmbcVersionDir(bin, ids[i]), t, t);
    }
    const stale = `${bin}/v/.tmp-dead-1-1`;
    fs.mkdirSync(stale, { recursive: true });
    const old = new Date(Date.now() - 3600_000);
    fs.utimesSync(stale, old, old);
    const removed = pruneDmbcVersions(2, bin);
    const left = fs.readdirSync(`${bin}/v`).sort();
    expect(left).toContain(ids[5]);
    expect(left).not.toContain('.tmp-dead-1-1');
    expect(left.length).toBe(3);
    expect(removed).toBe(4);
  });

  test('pruning leaves the current version and the one just superseded by default, and drops the per-key pointers an earlier layout wrote', () => {
    const v1 = publishDmbcVersion(pair('p1', 'one'), bin);
    const v2 = publishDmbcVersion(pair('p2', 'two'), bin);
    const v3 = publishDmbcVersion(pair('p3', 'three'), bin);
    fs.mkdirSync(`${bin}/by-key`, { recursive: true });
    fs.writeFileSync(`${bin}/by-key/k`, v1);
    for (const [i, id] of [v1, v2, v3].entries()) fs.utimesSync(dmbcVersionDir(bin, id), new Date(Date.now() - (10 - i) * 60_000), new Date(Date.now() - (10 - i) * 60_000));
    pruneDmbcVersions(undefined, bin);
    expect(fs.readdirSync(`${bin}/v`).sort()).toEqual([v2, v3].sort());
    expect(fs.existsSync(`${bin}/by-key`)).toBe(false);
  });
});

// `current` is one latest compiler for everyone and only moves forward along history.
describe('current moves forward only', () => {
  const git = (cwd: string, ...args: string[]) => {
    const r = spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd, encoding: 'utf8' });
    if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`);
    return r.stdout.trim();
  };
  function repo(): { root: string; first: string; second: string; side: string } {
    const root = path.join(tmp, 'repo').split(path.sep).join('/');
    fs.mkdirSync(root, { recursive: true });
    git(root, 'init', '-q');
    fs.writeFileSync(`${root}/a`, '1');
    git(root, 'add', '-A');
    git(root, 'commit', '-qm', 'first');
    const first = git(root, 'rev-parse', 'HEAD');
    fs.writeFileSync(`${root}/a`, '2');
    git(root, 'commit', '-qam', 'second');
    const second = git(root, 'rev-parse', 'HEAD');
    git(root, 'switch', '-q', '--detach', first);
    fs.writeFileSync(`${root}/b`, '3');
    git(root, 'add', '-A');
    git(root, 'commit', '-qm', 'side');
    return { root, first, second, side: git(root, 'rev-parse', 'HEAD') };
  }

  test('an older or diverged tree never moves current; a descendant does', () => {
    const { root, first, second, side } = repo();
    const newer = publishDmbcVersion(pair('new', 'new'), bin, { root, commit: second });
    expect(readCurrentDmbcVersion(bin)).toBe(newer);
    expect(currentIsCommit(second, bin)).toBe(true);
    expect(mayAdvanceCurrent(root, first, bin)).toBe(false);
    expect(mayAdvanceCurrent(root, side, bin)).toBe(false);
    publishDmbcVersion(pair('old', 'old'), bin, { root, commit: first });
    publishDmbcVersion(pair('side', 'side'), bin, { root, commit: side });
    expect(readCurrentDmbcVersion(bin)).toBe(newer);
    expect(currentIsCommit(second, bin)).toBe(true);
    // A descendant of the recorded commit advances it.
    git(root, 'switch', '-q', '--detach', second);
    fs.writeFileSync(`${root}/a`, '4');
    git(root, 'commit', '-qam', 'third');
    const third = git(root, 'rev-parse', 'HEAD');
    const newest = publishDmbcVersion(pair('newest', 'newest'), bin, { root, commit: third });
    expect(readCurrentDmbcVersion(bin)).toBe(newest);
    expect(currentIsCommit(third, bin)).toBe(true);
  });

  test('the first publication sets current', () => {
    const { root, first } = repo();
    expect(mayAdvanceCurrent(root, first, bin)).toBe(true);
    const id = publishDmbcVersion(pair('only', 'only'), bin, { root, commit: first });
    expect(readCurrentDmbcVersion(bin)).toBe(id);
  });
});

describe('stale cargo artifact signature', () => {
  test('recognizes a missing-method error and an ICE, not a plain type error', () => {
    expect(staleCargoArtifactSignature("error[E0599]: no method named `evict_to_budget` found for struct `Cache`")).toBe(true);
    expect(staleCargoArtifactSignature('error: internal compiler error: encountered incremental compilation error')).toBe(true);
    expect(staleCargoArtifactSignature('error[E0308]: mismatched types')).toBe(false);
  });
});
