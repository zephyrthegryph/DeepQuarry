// Run with `bun test tools/build/lib/seed.test.ts`.
import { afterEach, beforeEach, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { dmeValidationKey, isGeneratedDm, seedFromMainCheckout } from './seed';

let dir = '';
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dq-seed-'));
});
afterEach(() => {
  delete process.env.DQ_DATA_SEED;
  fs.rmSync(dir, { recursive: true, force: true });
});

test('seeds a missing file from DQ_DATA_SEED and never overwrites', () => {
  const src = path.join(dir, 'main');
  const wt = path.join(dir, 'wt');
  fs.mkdirSync(path.join(src, 'data'), { recursive: true });
  fs.mkdirSync(wt);
  fs.writeFileSync(path.join(src, 'data/x.json'), 'seed');
  process.env.DQ_DATA_SEED = src;
  expect(seedFromMainCheckout(wt, 'data/x.json')).not.toBeNull();
  expect(fs.readFileSync(path.join(wt, 'data/x.json'), 'utf-8')).toBe('seed');
  fs.writeFileSync(path.join(wt, 'data/x.json'), 'mine');
  expect(seedFromMainCheckout(wt, 'data/x.json')).toBeNull();
  expect(fs.readFileSync(path.join(wt, 'data/x.json'), 'utf-8')).toBe('mine');
});

test('DQ_DATA_SEED=off disables seeding', () => {
  process.env.DQ_DATA_SEED = 'off';
  expect(seedFromMainCheckout(dir, 'data/none.json')).toBeNull();
});

test('validation key ignores generated file stats but not real ones or the file list', () => {
  const files = ['code/a.dm', 'code/engine/_generated/g.dm'];
  const k = (stat: string, list = files) => dmeValidationKey('dme', list, (f) => (f.includes('_generated') ? stat : 'a'));
  expect(k('1')).toBe(k('2'));
  expect(k('1', [...files, 'code/b.dm'])).not.toBe(k('1'));
  expect(dmeValidationKey('dme', ['code/a.dm'], () => '1')).not.toBe(dmeValidationKey('dme', ['code/a.dm'], () => '2'));
  expect(isGeneratedDm('code/_generated/reads.dm')).toBe(true);
  expect(isGeneratedDm('code/_generated/om_notices.dm')).toBe(false);
});
