import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  dmbcVersionDir,
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
