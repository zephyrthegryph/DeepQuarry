// Run with `bun test tools/build/lib/free_port.test.ts`.
import { afterEach, beforeEach, expect, test } from 'bun:test';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { claimFreePort, freePort, shouldRetryBoot, tryClaimPort } from './free_port';

let dir = '';
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dq-ports-'));
});
afterEach(() => fs.rmSync(dir, { recursive: true, force: true }));

test('a claimed port is refused to the next claimer until released', () => {
  const a = tryClaimPort(dir, 41000, 1);
  expect(a).not.toBeNull();

  const mine = tryClaimPort(dir, 41001);
  expect(mine).not.toBeNull();
  expect(tryClaimPort(dir, 41001, process.pid + 100000)).toBeNull();
  mine?.release();
  expect(tryClaimPort(dir, 41001, process.pid + 100000)).not.toBeNull();
});

test('a stale lock of a dead owner is replaced', () => {
  fs.writeFileSync(path.join(dir, '41002.lock'), '2147483646');
  expect(tryClaimPort(dir, 41002)).not.toBeNull();
});

test('claimFreePort skips a candidate another world holds', async () => {
  const held = tryClaimPort(dir, 41003);
  expect(held).not.toBeNull();
  const candidates = [41003, 41003, 41004];
  const claim = await claimFreePort(async () => candidates.shift() as number, dir);
  expect(claim.port).toBe(41004);
});

test('freePort is bindable on every interface', async () => {
  const port = await freePort();
  await new Promise<void>((resolve, reject) => {
    const s = net.createServer();
    s.on('error', reject);
    s.listen(port, '0.0.0.0', () => s.close(() => resolve()));
  });
});

test('only a fast death without results is retried, a bounded number of times', () => {
  expect(shouldRetryBoot(3000, false, false, 1)).toBe(true);
  expect(shouldRetryBoot(3000, true, false, 1)).toBe(false);
  expect(shouldRetryBoot(3000, false, true, 1)).toBe(false);
  expect(shouldRetryBoot(120000, false, false, 1)).toBe(false);
  expect(shouldRetryBoot(3000, false, false, 4)).toBe(false);
});
