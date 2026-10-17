import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  dmbcCacheKey,
  dmbcVersionDir,
  keyPointer,
  mayAdvanceCurrent,
  treeDmbcVersion,
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

  test('a process pinned to a version keeps it across a republish', () => {
    const v1 = publishDmbcVersion(pair('built1', 'one'), bin);
    unpinDmbcVersion(bin);
    expect(pinnedDmbcVersion(bin)).toBe(v1);
    const v2 = publishDmbcVersion(pair('built2', 'two'), bin);
    // publishing unpins the publisher itself (it wants its own result); a different process pinned earlier would still hold v1
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
});

describe('stale cargo artifact signature', () => {
  test('recognizes a missing-method error and an ICE, not a plain type error', () => {
    expect(staleCargoArtifactSignature("error[E0599]: no method named `evict_to_budget` found for struct `Cache`")).toBe(true);
    expect(staleCargoArtifactSignature('error: internal compiler error: encountered incremental compilation error')).toBe(true);
    expect(staleCargoArtifactSignature('error[E0308]: mismatched types')).toBe(false);
  });
});

// A checkout selects its compiler by its own sources; `current` only moves forward along history.
describe('per-checkout compiler selection', () => {
  const git = (cwd: string, ...args: string[]) => {
    const r = spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd, encoding: 'utf8' });
    if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`);
    return r.stdout.trim();
  };
  function repo(): { root: string; first: string; second: string } {
    const root = path.join(tmp, 'repo').split(path.sep).join('/');
    for (const file of ['tools/dmb/Cargo.toml', 'tools/dmb/Cargo.lock', 'tools/dmb/build.rs', 'tools/dmb/src/lib.rs', 'tools/dmb/crates/a/lib.rs', 'tools/dmb/patches/p.patch', 'tools/dmb/fixtures/native_template.bin']) {
      fs.mkdirSync(path.dirname(`${root}/${file}`), { recursive: true });
      fs.writeFileSync(`${root}/${file}`, 'one');
    }
    git(root, 'init', '-q');
    git(root, 'add', '-A');
    git(root, 'commit', '-qm', 'first');
    const first = git(root, 'rev-parse', 'HEAD');
    fs.writeFileSync(`${root}/tools/dmb/src/lib.rs`, 'two');
    git(root, 'commit', '-qam', 'second');
    return { root, first, second: git(root, 'rev-parse', 'HEAD') };
  }
  const keyOf = (root: string) => {
    const k = dmbcCacheKey(root);
    if ('bypass' in k) throw new Error(k.bypass);
    return k.key;
  };

  test('restoring an older tree compiler does not move current back, and each tree keeps its own version', () => {
    const { root, first, second } = repo();
    git(root, 'switch', '-q', '--detach', first);
    const keyFirst = keyOf(root);
    git(root, 'switch', '-q', '--detach', second);
    const keySecond = keyOf(root);
    const newer = publishDmbcVersion(pair('new', 'new'), bin, { root, key: keySecond, commit: second });
    expect(readCurrentDmbcVersion(bin)).toBe(newer);
    expect(mayAdvanceCurrent(root, first, bin)).toBe(false);
    const older = publishDmbcVersion(pair('old', 'old'), bin, { root, key: keyFirst, commit: first });
    expect(readCurrentDmbcVersion(bin)).toBe(newer);
    expect(fs.readFileSync(keyPointer(bin, keyFirst), 'utf8').trim()).toBe(older);
    // Each tree selects the version built from its own sources, whatever current says.
    git(root, 'switch', '-q', '--detach', first);
    unpinDmbcVersion(bin);
    expect(treeDmbcVersion(root, bin)).toBe(older);
    git(root, 'switch', '-q', '--detach', second);
    expect(treeDmbcVersion(root, bin)).toBe(newer);
    // A later commit still advances current.
    expect(mayAdvanceCurrent(root, second, bin)).toBe(true);
  });

  test('a dirty compiler tree runs its own build and never moves current or another tree', () => {
    const { root, second } = repo();
    const published = publishDmbcVersion(pair('main', 'main'), bin, { root, key: keyOf(root), commit: second });
    fs.writeFileSync(`${root}/tools/dmb/src/lib.rs`, 'edited');
    const own = publishDmbcVersion(pair('dev', 'dev'), bin, { root });
    expect(own).not.toBe(published);
    expect(readCurrentDmbcVersion(bin)).toBe(published);
    unpinDmbcVersion(bin);
    expect(treeDmbcVersion(root, bin)).toBe(own);
    fs.writeFileSync(`${root}/tools/dmb/src/lib.rs`, 'two');
    unpinDmbcVersion(bin);
    expect(treeDmbcVersion(root, bin)).toBe(published);
  });
});
