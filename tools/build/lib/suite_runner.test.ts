// Tests for the sharded full suite's runner pieces (lib/suite_runner.ts). Run with `bun test tools/build/lib/suite_runner.test.ts`.
import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  DURATIONS_MAX_AGE_DAYS,
  DURATIONS_MAX_ENTRIES,
  measuredDurations,
  neverRan,
  packShards,
  parseRunLog,
  pruneDurations,
  readDurations,
  recordDurations,
  suiteStalenessParams,
} from './suite_runner';

describe('staleness mode of a whole-tier shard', () => {
  test('periodic every 200 by default', () => {
    expect(suiteStalenessParams({}, {})).toEqual({ staleness: 'periodic', 'staleness-full-every': '200' });
  });
  test('DQ_STALENESS=full keeps the full sweep at every test end', () => {
    expect(suiteStalenessParams({ DQ_STALENESS: 'full' }, {})).toEqual({});
  });
  test('the interval and the bounded mode come from the environment', () => {
    expect(suiteStalenessParams({ DQ_STALENESS_FULL_EVERY: '50' }, {})).toEqual({ staleness: 'periodic', 'staleness-full-every': '50' });
    expect(suiteStalenessParams({ DQ_STALENESS: 'bounded' }, {})).toEqual({ staleness: 'bounded' });
    expect(suiteStalenessParams({ DQ_STALENESS_FULL_EVERY: '0' }, {})['staleness-full-every']).toBe('200');
  });
  test('a mode named in DQ_WORLD_PARAMS wins', () => {
    expect(suiteStalenessParams({}, { staleness: 'full' })).toEqual({});
    expect(suiteStalenessParams({}, { staleness: 'periodic', 'staleness-full-every': '7' })).toEqual({});
    expect(suiteStalenessParams({}, { staleness: 'periodic' })).toEqual({ 'staleness-full-every': '200' });
  });
});

const LOG = [
  '[t] RUNTIME: ::group::(1/5) /datum/unit_test/a',
  '[t] RUNTIME: PASS /datum/unit_test/a 0.5s',
  '[t] RUNTIME: ::endgroup::',
  '[t] RUNTIME: ::group::(2/5) /datum/unit_test/b',
  '[t] RUNTIME: ::error::FAIL /datum/unit_test/b 1.25s',
  '[t] RUNTIME: ::endgroup::',
  '[t] RUNTIME: ::group::(3/5) /datum/unit_test/c',
  '[t] RUNTIME: PASS /datum/unit_test/c 0.1s',
  '[t] RUNTIME: ::error::FAIL /datum/unit_test/c 0.1s (leaked objects)',
  '[t] RUNTIME: ::endgroup::',
  '[t] RUNTIME: ::group::(4/5) /datum/unit_test/d',
  '[t] RUNTIME: SKIPPED Skipped run on map Virgo_minitest.',
  '[t] RUNTIME: ::endgroup::',
  '[t] RUNTIME: ::group::(5/5) /datum/unit_test/e',
].join('\n');

describe('salvage of a killed shard', () => {
  test('pass, fail, leak after pass, skip and the in-flight test', () => {
    const run = parseRunLog(LOG);
    expect(run.results['/datum/unit_test/a'].status).toBe(0);
    expect(run.results['/datum/unit_test/a'].duration_ds).toBe(5);
    expect(run.results['/datum/unit_test/b'].status).toBe(1);
    expect(run.results['/datum/unit_test/c'].status).toBe(1);
    expect(run.results['/datum/unit_test/d'].status).toBe(2);
    expect(run.results['/datum/unit_test/e']).toBeUndefined();
    expect(run.inFlight).toBe('/datum/unit_test/e');
    expect(run.position).toEqual({ index: 5, total: 5 });
  });
  test('a finished log has no test in flight', () => {
    expect(parseRunLog(LOG.split('\n').slice(0, -1).join('\n')).inFlight).toBeNull();
  });
  test('never-ran lists the in-flight test first, then every assigned test without a result', () => {
    const run = parseRunLog(LOG);
    const expected = ['/datum/unit_test/a', '/datum/unit_test/e', '/datum/unit_test/f', '/datum/unit_test/g'];
    expect(neverRan(expected, run)).toEqual(['/datum/unit_test/e', '/datum/unit_test/f', '/datum/unit_test/g']);
  });
  test('a failure is never overwritten by a later pass line', () => {
    const run = parseRunLog('::group::(1/1) /x\n::error::FAIL /x 1s\nPASS /x 1s\n::endgroup::');
    expect(run.results['/x'].status).toBe(1);
  });
});

describe('duration history', () => {
  const dir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'dq-durations-'));
  test('records, merges, reads back and survives a corrupt file', () => {
    const d = dir();
    try {
      expect(readDurations(d).size).toBe(0);
      recordDurations(new Map([['a', 10], ['b', 20]]), d);
      recordDurations(new Map([['b', 30], ['c', 5]]), d);
      expect([...readDurations(d)].sort()).toEqual([['a', 10], ['b', 30], ['c', 5]]);
      fs.writeFileSync(path.join(d, 'durations.json'), '{half');
      expect(readDurations(d).size).toBe(0);
      expect(recordDurations(new Map([['z', 1]]), d)).toBe(1);
    } finally {
      fs.rmSync(d, { recursive: true, force: true });
    }
  });
  test('off writes and reads nothing', () => {
    expect(recordDurations(new Map([['a', 1]]), null)).toBe(0);
    expect(readDurations(null).size).toBe(0);
  });
  test('the age limit drops old entries and the entry cap keeps the newest', () => {
    const now = 1_000_000_000_000;
    const old = now - (DURATIONS_MAX_AGE_DAYS + 1) * 86_400_000;
    expect(Object.keys(pruneDurations({ a: { ds: 1, at: old }, b: { ds: 1, at: now } }, now))).toEqual(['b']);
    const many: Record<string, { ds: number; at: number }> = {};
    for (let i = 0; i < DURATIONS_MAX_ENTRIES + 10; i++) many[`t${i}`] = { ds: 1, at: now - i };
    const kept = pruneDurations(many, now);
    expect(Object.keys(kept).length).toBe(DURATIONS_MAX_ENTRIES);
    expect(kept.t0).toBeDefined();
    expect(kept[`t${DURATIONS_MAX_ENTRIES + 5}`]).toBeUndefined();
  });
  test('measured durations skip skipped tests, sweeps and zero-time tests', () => {
    const m = measuredDurations({ a: { status: 0, duration_ds: 4 }, b: { status: 2, duration_ds: 9 }, c: { status: 0, duration_ds: 0 }, sweep: { status: 0, duration_ds: 50 }, d: { status: 1, duration_ds: 7 } }, (n) => n === 'sweep');
    expect([...m].sort()).toEqual([['a', 4], ['d', 7]]);
  });
});

describe('balance', () => {
  test('by measured time, not by count', () => {
    const names = ['big', 'm1', 'm2', 's1', 's2', 's3', 's4'];
    const d = new Map([['big', 100], ['m1', 30], ['m2', 30], ['s1', 10], ['s2', 10], ['s3', 10], ['s4', 10]]);
    const { shards, loads } = packShards(names, 2, d, 5);
    expect(shards[0]).toContain('big');
    expect(Math.abs(loads[0] - loads[1])).toBeLessThanOrEqual(10);
    expect(shards[0].length).not.toBe(shards[1].length);
  });
  test('an unknown test weighs the median of the known ones; counted', () => {
    const d = new Map([['a', 10], ['b', 20], ['c', 30]]);
    const r = packShards(['a', 'b', 'c', 'new'], 2, d, 5);
    expect(r.unknown).toBe(1);
    expect(r.loads[0] + r.loads[1]).toBe(10 + 20 + 30 + 20);
  });
  test('with no history it falls back to the default weight', () => {
    const r = packShards(['a', 'b', 'c', 'd'], 2, new Map(), 5);
    expect(r.shards[0].length).toBe(2);
    expect(r.loads).toEqual([10, 10]);
  });
});
