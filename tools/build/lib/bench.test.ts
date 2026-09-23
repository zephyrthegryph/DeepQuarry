// Unit tests for the bench store: shared-dir resolution, metric-class
// comparison gating and load-similarity rules. Run with `bun test
// tools/build/lib/bench.test.ts` (or `bun test` from the repo root).
import { describe, expect, test, afterEach } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  benchRunsDir,
  benchStoreDir,
  benchExclusiveLockDir,
  ddSlotBaseDir,
  compareRuns,
  loadSimilar,
  statsOf,
  BENCH_RUNS_DIR,
  type BenchRun,
  type LoadContext,
} from './bench';

const ENV_KEYS = ['DQ_BENCH_STORE', 'DQ_BENCH_EXCLUSIVE_LOCK', 'DQ_DD_SLOT_BASE'] as const;
const savedEnv: Record<string, string | undefined> = {};
for (const k of ENV_KEYS) savedEnv[k] = process.env[k];

afterEach(() => {
  for (const k of ENV_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k];
    else process.env[k] = savedEnv[k];
  }
});

describe('shared store resolution', () => {
  test('falls back to the local per-worktree dir when DQ_BENCH_STORE is unset', () => {
    delete process.env.DQ_BENCH_STORE;
    expect(benchStoreDir()).toBeNull();
    expect(benchRunsDir()).toBe(BENCH_RUNS_DIR);
  });

  test('DQ_BENCH_STORE redirects runs/, the exclusive lock and the dd-slot base', () => {
    process.env.DQ_BENCH_STORE = '/shared/.dq-bench';
    expect(benchRunsDir()).toBe(path.join('/shared/.dq-bench', 'runs'));
    expect(benchExclusiveLockDir()).toBe(path.join('/shared/.dq-bench', '.dq-bench-exclusive'));
    expect(ddSlotBaseDir()).toBe(path.join('/shared', '.dq-dd-slot-'));
  });

  test('explicit overrides win over the derived defaults', () => {
    process.env.DQ_BENCH_STORE = '/shared/.dq-bench';
    process.env.DQ_BENCH_EXCLUSIVE_LOCK = '/other/lock';
    process.env.DQ_DD_SLOT_BASE = '/other/slot-';
    expect(benchExclusiveLockDir()).toBe('/other/lock');
    expect(ddSlotBaseDir()).toBe('/other/slot-');
  });
});

describe('statsOf', () => {
  test('defaults to the timing class and computes median/stdev', () => {
    const s = statsOf([1, 2, 3, 4, 5], 'ms', 'lower');
    expect(s.class).toBe('timing');
    expect(s.median).toBe(3);
    expect(s.n).toBe(5);
  });

  test('carries an explicit count class through', () => {
    const s = statsOf([10, 10, 10], 'calls', 'lower', 'count');
    expect(s.class).toBe('count');
  });
});

describe('loadSimilar', () => {
  const base = (over: Partial<LoadContext> = {}): LoadContext => ({
    machine_id: 'm',
    exclusive: false,
    other_dreamdaemon: 0,
    other_dm: 0,
    cargo_rustc: 0,
    cpu_percent: 20,
    ...over,
  });

  test('both exclusive is always similar, even with very different CPU readings', () => {
    expect(loadSimilar(base({ exclusive: true, cpu_percent: 5 }), base({ exclusive: true, cpu_percent: 95 }))).toBe(true);
  });

  test('one exclusive and one not is never similar', () => {
    expect(loadSimilar(base({ exclusive: true }), base({ exclusive: false }))).toBe(false);
  });

  test('quiet, close-CPU non-exclusive runs are similar', () => {
    expect(loadSimilar(base({ cpu_percent: 20 }), base({ cpu_percent: 30 }))).toBe(true);
  });

  test('a busy machine (many concurrent processes) is not similar even at matching CPU', () => {
    expect(loadSimilar(base({ cargo_rustc: 5, cpu_percent: 50 }), base({ cargo_rustc: 5, cpu_percent: 50 }))).toBe(false);
  });

  test('a big CPU gap is not similar', () => {
    expect(loadSimilar(base({ cpu_percent: 10 }), base({ cpu_percent: 60 }))).toBe(false);
  });

  test('missing load context (older stored runs) is never similar', () => {
    expect(loadSimilar(undefined, base())).toBe(false);
  });
});

describe('compareRuns metric-class gating', () => {
  function run(overrides: {
    commit?: string;
    load: LoadContext;
    summary: BenchRun['summary'];
  }): BenchRun {
    return {
      id: `id-${overrides.commit ?? 'x'}`,
      timestamp: new Date().toISOString(),
      commit: overrides.commit ?? 'abc1234567',
      branch: 'test',
      dirty_files: 0,
      host: 'h',
      platform: 'win32',
      kind: 'bench',
      label: null,
      map: 'virgo_minitest',
      defines: [],
      scenarios_requested: [],
      args: [],
      iterations: [],
      failures: [],
      summary: overrides.summary,
      load: overrides.load,
    };
  }

  const quiet: LoadContext = { machine_id: 'm', exclusive: false, other_dreamdaemon: 0, other_dm: 0, cargo_rustc: 0, cpu_percent: 15 };
  const busy: LoadContext = { machine_id: 'm', exclusive: false, other_dreamdaemon: 3, other_dm: 2, cargo_rustc: 4, cpu_percent: 90 };

  test('a COUNT metric compares directly even under very different load', () => {
    const base = run({ summary: { scenario: { ffi_calls: statsOf([100], 'calls', 'lower', 'count') } }, load: quiet });
    const head = run({ summary: { scenario: { ffi_calls: statsOf([130], 'calls', 'lower', 'count') } }, load: busy });
    const rows = compareRuns(base, head, 5);
    const row = rows.find((r) => r.metric === 'ffi_calls');
    expect(row?.verdict).toBe('regression');
    expect(row?.class).toBe('count');
  });

  test('a TIMING metric under dissimilar load is not_comparable, not silently skipped', () => {
    const base = run({ summary: { scenario: { window_tick_avg: statsOf([10], '%', 'lower', 'timing') } }, load: quiet });
    const head = run({ summary: { scenario: { window_tick_avg: statsOf([50], '%', 'lower', 'timing') } }, load: busy });
    const rows = compareRuns(base, head, 5);
    const row = rows.find((r) => r.metric === 'window_tick_avg');
    expect(row?.verdict).toBe('not_comparable');
    expect(Number.isNaN(row?.change_pct)).toBe(true);
  });

  test('a TIMING metric compares normally when both runs are quiet', () => {
    const base = run({ summary: { scenario: { window_tick_avg: statsOf([10, 10, 10], '%', 'lower', 'timing') } }, load: quiet });
    const head = run({ summary: { scenario: { window_tick_avg: statsOf([20, 20, 20], '%', 'lower', 'timing') } }, load: quiet });
    const rows = compareRuns(base, head, 5);
    const row = rows.find((r) => r.metric === 'window_tick_avg');
    expect(row?.verdict).toBe('regression');
  });

  test('a TIMING metric compares normally when both runs are exclusive, regardless of their CPU reading', () => {
    const exA: LoadContext = { ...busy, exclusive: true };
    const exB: LoadContext = { ...quiet, exclusive: true };
    const base = run({ summary: { scenario: { window_tick_avg: statsOf([10, 10, 10], '%', 'lower', 'timing') } }, load: exA });
    const head = run({ summary: { scenario: { window_tick_avg: statsOf([10.5, 10.5, 10.5], '%', 'lower', 'timing') } }, load: exB });
    const rows = compareRuns(base, head, 5);
    const row = rows.find((r) => r.metric === 'window_tick_avg');
    expect(row?.verdict).toBe('unchanged');
  });
});
