// Unit tests for the bench store: shared-dir resolution, metric-class
// comparison gating and load-similarity rules. Run with `bun test
// tools/build/lib/bench.test.ts` (or `bun test` from the repo root).
import { describe, expect, test, afterEach } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  acquireBenchExclusiveLock,
  benchRunsDir,
  benchStoreDir,
  benchExclusiveLockDir,
  ddSlotBaseDir,
  compareRuns,
  formatComparison,
  gateFor,
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

describe('bench-compare gates', () => {
  // Kernel measurement metrics (code/modules/benchmarks/kernel_metrics.dm): input_p99 and breaches may not rise,
  // and a system's p99_ms rising more than 20% is named. Timing metrics still need similar load to compare.
  const quiet: LoadContext = { machine_id: 'm', exclusive: false, other_dreamdaemon: 0, other_dm: 0, cargo_rustc: 0, cpu_percent: 15 };
  const busy: LoadContext = { machine_id: 'm', exclusive: false, other_dreamdaemon: 3, other_dm: 2, cargo_rustc: 4, cpu_percent: 90 };

  function run(summary: BenchRun['summary'], load: LoadContext = quiet): BenchRun {
    return {
      id: 'id', timestamp: new Date().toISOString(), commit: 'abc1234567', branch: 'test', dirty_files: 0, host: 'h',
      platform: 'win32', kind: 'bench', label: null, map: 'virgo_minitest', defines: [], scenarios_requested: [],
      args: [], iterations: [], failures: [], summary, load,
    };
  }

  const timing = (values: number[], unit = 'ms') => statsOf(values, unit, 'lower', 'timing');
  const verdictOf = (base: BenchRun, head: BenchRun, metric: string) =>
    compareRuns(base, head, 5).find((r) => r.metric === metric);

  test('gateFor covers the gated metric families only', () => {
    expect(gateFor('input_p99')).toBeDefined();
    expect(gateFor('input_p99_ticks')).toBeDefined();
    expect(gateFor('system.mc_air.breaches')).toBeDefined();
    expect(gateFor('system.life.p99_ms')).toBeDefined();
    expect(gateFor('system.life.ms_per_s')).toBeUndefined();
    expect(gateFor('tick_p99')).toBeUndefined();
    expect(gateFor('input_p50')).toBeUndefined();
  });

  test('a rise in input_p99 is a regression even below the generic 5% threshold', () => {
    const base = run({ idle: { input_p99: timing([10]) } });
    const head = run({ idle: { input_p99: timing([10.3]) } });
    const row = verdictOf(base, head, 'input_p99');
    expect(row?.verdict).toBe('regression');
    expect(row?.gate).toContain('input_p99');
    expect(formatComparison(compareRuns(base, head, 5), true)).toContain('gate: input_p99 must not rise');
  });

  test('a rise under the metric resolution is not a regression', () => {
    const base = run({ idle: { input_p99: timing([0.005]) } });
    const head = run({ idle: { input_p99: timing([0.03]) } });
    expect(verdictOf(base, head, 'input_p99')?.gate).toBeUndefined();
    expect(verdictOf(base, head, 'input_p99')?.verdict).toBe('unchanged');
  });

  test('input_p99 falling is not a regression', () => {
    const base = run({ idle: { input_p99: timing([10]) } });
    const head = run({ idle: { input_p99: timing([4]) } });
    const row = verdictOf(base, head, 'input_p99');
    expect(row?.verdict).toBe('improvement');
    expect(row?.gate).toBeUndefined();
  });

  test('a rise within the runs own noise does not trip the gate', () => {
    const base = run({ idle: { input_p99: timing([8, 10, 12]) } });
    const head = run({ idle: { input_p99: timing([8.5, 10.5, 12.5]) } });
    expect(verdictOf(base, head, 'input_p99')?.verdict).toBe('unchanged');
  });

  test('a breach appearing where there were none is a regression, and equal counts are not', () => {
    const base = run({ life_sweep: { 'system.life.breaches': timing([0], 'breaches'), 'system.mc_air.breaches': timing([2], 'breaches') } });
    const head = run({ life_sweep: { 'system.life.breaches': timing([1], 'breaches'), 'system.mc_air.breaches': timing([2], 'breaches') } });
    const rows = compareRuns(base, head, 5);
    expect(rows.find((r) => r.metric === 'system.life.breaches')?.verdict).toBe('regression');
    expect(rows.find((r) => r.metric === 'system.life.breaches')?.gate).toContain('breaches');
    expect(rows.find((r) => r.metric === 'system.mc_air.breaches')?.verdict).toBe('unchanged');
  });

  test('a system p99_ms rising over 20% is named by the gate; a smaller rise is only a generic regression', () => {
    const base = run({ idle: { 'system.life.p99_ms': timing([10]), 'system.machines.p99_ms': timing([10]) } });
    const head = run({ idle: { 'system.life.p99_ms': timing([12.5]), 'system.machines.p99_ms': timing([11]) } });
    const rows = compareRuns(base, head, 5);
    expect(rows.find((r) => r.metric === 'system.life.p99_ms')?.gate).toContain('p99_ms');
    expect(rows.find((r) => r.metric === 'system.machines.p99_ms')?.verdict).toBe('regression');
    expect(rows.find((r) => r.metric === 'system.machines.p99_ms')?.gate).toBeUndefined();
  });

  test('a gated timing metric under dissimilar load is not comparable, not a regression', () => {
    const base = run({ idle: { input_p99: timing([1]) } }, quiet);
    const head = run({ idle: { input_p99: timing([50]) } }, busy);
    expect(verdictOf(base, head, 'input_p99')?.verdict).toBe('not_comparable');
  });

  test('a metric missing from the base (an older stored run) is new, never a regression', () => {
    const base = run({ idle: { tick_p99: timing([10], '%') } });
    const head = run({ idle: { tick_p99: timing([10], '%'), input_p99: timing([40]) } });
    expect(verdictOf(base, head, 'input_p99')?.verdict).toBe('new');
  });
});

describe('acquireBenchExclusiveLock', () => {
  // Regression test for a real deadlock found by actually running
  // bench-baseline end-to-end: when DQ_BENCH_STORE's directory doesn't exist
  // yet (a fresh machine/store), the first fs.mkdirSync(lockDir) attempt used
  // to throw ENOENT (missing parent), which looked exactly like "someone else
  // holds the lock" (readIntFile() on the nonexistent pid/started files
  // returned 0, so it was always judged "stale"), so it tried to rmSync a
  // directory that never existed and immediately retried -- forever, never
  // creating the lock or the parent directory.
  test('creates its parent directory instead of looping forever when the store is missing', async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dq-bench-lock-test-'));
    process.env.DQ_BENCH_STORE = path.join(tmp, 'does', 'not', 'exist', 'yet');
    try {
      expect(fs.existsSync(benchExclusiveLockDir())).toBe(false);
      const lock = await acquireBenchExclusiveLock();
      expect(fs.existsSync(benchExclusiveLockDir())).toBe(true);
      lock.release();
      expect(fs.existsSync(benchExclusiveLockDir())).toBe(false);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });

  test('a second acquire waits for the first to release', async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dq-bench-lock-test-'));
    process.env.DQ_BENCH_STORE = tmp;
    try {
      const first = await acquireBenchExclusiveLock();
      let secondAcquired = false;
      const secondPromise = acquireBenchExclusiveLock(20 * 60 * 1000, 50).then((lock) => {
        secondAcquired = true;
        return lock;
      });
      await new Promise((resolve) => setTimeout(resolve, 150));
      expect(secondAcquired).toBe(false);
      first.release();
      const second = await secondPromise;
      expect(secondAcquired).toBe(true);
      second.release();
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });
});
