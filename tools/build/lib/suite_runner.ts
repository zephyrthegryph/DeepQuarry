// Runner-side pieces of the sharded full suite (`dm-test`): the staleness mode a shard's world runs, the shared duration history that
// balances shards, and the salvage of a killed shard's results from its log. Pure functions where possible, so
// tools/build/lib/suite_runner.test.ts can check them; build.ts does the I/O around them.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// ---------------------------------------------------------------------------
// Staleness mode. The checker's end-of-test sweep costs about 0.18 s per test in "full" mode (about 10 minutes of a shard); a whole-tier shard
// runs "periodic": bounded at every test end plus a full sweep every N tests and after the last one (code/engine/change/staleness.dm). A finding
// still fails the suite, attributed to the tests since the last clean full sweep.

export const STALENESS_FULL_EVERY_DEFAULT = 200;

/**
 * The world params that set the staleness mode of a whole-tier shard. `existing` is what DQ_WORLD_PARAMS already set (it wins: whoever
 * names a mode means it). DQ_STALENESS=full keeps the old full sweep at every test end, DQ_STALENESS=bounded the focused-run mode, and
 * DQ_STALENESS_FULL_EVERY=N sets the interval of the periodic mode (default 200).
 */
export function suiteStalenessParams(env: Record<string, string | undefined>, existing: Record<string, string>): Record<string, string> {
  const params: Record<string, string> = {};
  if (existing.staleness === undefined) {
    const mode = env.DQ_STALENESS === 'full' ? null : env.DQ_STALENESS === 'bounded' ? 'bounded' : 'periodic';
    if (mode) params.staleness = mode;
  }
  const every = Number(env.DQ_STALENESS_FULL_EVERY);
  const mode = existing.staleness ?? params.staleness;
  if (mode === 'periodic' && existing['staleness-full-every'] === undefined) {
    params['staleness-full-every'] = String(Number.isInteger(every) && every >= 1 ? every : STALENESS_FULL_EVERY_DEFAULT);
  }
  return params;
}

// ---------------------------------------------------------------------------
// Salvage. The world writes its results JSON only when the whole suite is done, so a shard the watchdog kills would lose everything. Its
// runtime.log has a "::group::(i/N) path" line when a test starts and "PASS path 1.2s" or "::error::FAIL path 1.2s" when it ends
// (code/modules/unit_tests/unit_test.dm RunUnitTest), and "SKIPPED ..." right after the group line of a skipped test.

export type SalvagedEntry = { status: number; message: string; name: string; duration_ds: number; runtimes: number; salvaged: true };

export type SalvagedRun = {
  results: Record<string, SalvagedEntry>;
  /** The test that had started and not ended when the log stopped (the one the kill interrupted), if any. */
  inFlight: string | null;
  /** The "(i/N)" of the last group line: how far the shard got and how many it was asked for. */
  position: { index: number; total: number } | null;
};

export function parseRunLog(text: string): SalvagedRun {
  const results: Record<string, SalvagedEntry> = {};
  let current: string | null = null;
  let position: SalvagedRun['position'] = null;
  const set = (name: string, status: number, seconds: number, message: string) => {
    const prior = results[name];
    // A test prints PASS and then FAIL (a leak found after it): the failure stays.
    const failed = status === 1 || prior?.status === 1;
    results[name] = {
      status: failed ? 1 : status,
      message: prior?.status === 1 && status !== 1 ? prior.message : message,
      name,
      duration_ds: Math.round(seconds * 10),
      runtimes: 0,
      salvaged: true,
    };
  };
  for (const line of text.split(/\r?\n/)) {
    const group = /::group::\((\d+)\/(\d+)\) (\S+)/.exec(line);
    if (group) {
      current = group[3];
      position = { index: Number(group[1]), total: Number(group[2]) };
      continue;
    }
    if (/::endgroup::/.test(line)) {
      if (current && !results[current]) {
        // an endgroup without a PASS or FAIL before it: a skipped test
        results[current] = { status: 2, message: 'skipped (salvaged from the log)', name: current, duration_ds: 0, runtimes: 0, salvaged: true };
      }
      current = null;
      continue;
    }
    const fail = /::error::FAIL (\S+)(?: ([\d.]+)s)?/.exec(line);
    if (fail) {
      set(fail[1], 1, Number(fail[2] ?? 0), 'FAILED (salvaged from the log: the world was killed before it wrote its results; see tests.log for the reasons)');
      continue;
    }
    const pass = /\bPASS (\S+) ([\d.]+)s/.exec(line);
    if (pass) set(pass[1], 0, Number(pass[2]), '');
  }
  return { results, inFlight: current && !results[current] ? current : null, position };
}

/**
 * What a killed shard did not do: its assigned tests (and the sweeps every shard runs) with no result, the in-flight one first. `expected` is
 * the names the shard was asked to run.
 */
export function neverRan(expected: string[], salvaged: SalvagedRun): string[] {
  const missing = expected.filter((name) => !salvaged.results[name] && name !== salvaged.inFlight);
  return salvaged.inFlight ? [salvaged.inFlight, ...missing] : missing;
}

// ---------------------------------------------------------------------------
// Duration history: each test's last measured duration (deciseconds), shared by every worktree so a fresh pool worktree balances by time and
// not by count. A rebuildable cache under E:/dq-cache (AGENTS.md "disk hygiene"), not a committed file: the numbers move with every machine,
// compiler and test edit, so a committed tools/ci/test_durations.json would be a conflict magnet on every lane (each full run rewrites it) and go
// stale between refreshes, while the cache is written by every run that measures a test (a focused run, a shard) and read by all. The cap is
// DURATIONS_MAX_ENTRIES names and DURATIONS_MAX_AGE_DAYS since a test was last measured; both are applied on every write.

export const DURATIONS_MAX_ENTRIES = 20000;
export const DURATIONS_MAX_AGE_DAYS = 45;

export type DurationEntry = { ds: number; at: number };
export type DurationFile = { schema: 1; tests: Record<string, DurationEntry> };

export function durationsDir(env: Record<string, string | undefined> = process.env): string | null {
  const set = env.DQ_TEST_DURATIONS_DIR;
  if (set === 'off') return null;
  if (set) return set;
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/test-durations';
  return path.join(os.homedir(), '.cache', 'dq', 'test-durations');
}

export function readDurations(dir: string | null = durationsDir()): Map<string, number> {
  const out = new Map<string, number>();
  if (!dir) return out;
  try {
    const file = JSON.parse(fs.readFileSync(path.join(dir, 'durations.json'), 'utf-8')) as DurationFile;
    for (const [name, entry] of Object.entries(file.tests ?? {})) if (Number.isFinite(entry?.ds) && entry.ds >= 0) out.set(name, entry.ds);
  } catch {
    // missing or half-written: no history
  }
  return out;
}

/** Drops entries older than the age limit, then the oldest beyond the entry cap. */
export function pruneDurations(tests: Record<string, DurationEntry>, now: number): Record<string, DurationEntry> {
  const horizon = now - DURATIONS_MAX_AGE_DAYS * 86_400_000;
  let kept = Object.entries(tests).filter(([, e]) => e && e.at >= horizon && Number.isFinite(e.ds));
  if (kept.length > DURATIONS_MAX_ENTRIES) {
    kept = kept.sort((a, b) => b[1].at - a[1].at).slice(0, DURATIONS_MAX_ENTRIES);
  }
  return Object.fromEntries(kept);
}

/**
 * Merges measured durations into the shared file: read, merge, prune, write a temp file and rename it over (a reader never sees half a
 * file; two writers at once lose at most one run's numbers, which the next run measures again). Returns how many entries it wrote.
 */
export function recordDurations(measured: Map<string, number>, dir: string | null = durationsDir(), now: number = Date.now()): number {
  if (!dir || measured.size === 0) return 0;
  try {
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'durations.json');
    let tests: Record<string, DurationEntry> = {};
    try {
      tests = (JSON.parse(fs.readFileSync(file, 'utf-8')) as DurationFile).tests ?? {};
    } catch {
      // first write, or a corrupt file: start again
    }
    for (const [name, ds] of measured) tests[name] = { ds, at: now };
    tests = pruneDurations(tests, now);
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ schema: 1, tests } satisfies DurationFile));
    fs.renameSync(tmp, file);
    return Object.keys(tests).length;
  } catch {
    return 0;
  }
}

/** The measured (name -> ds) of a run's results: tests that ran (not skipped) and took time, minus the ones `skip` names (sweeps self-divide). */
export function measuredDurations(results: Record<string, { status: number; duration_ds?: number }>, skip: (name: string) => boolean): Map<string, number> {
  const out = new Map<string, number>();
  for (const [name, entry] of Object.entries(results)) {
    if (entry.status === 2 || skip(name)) continue;
    if (typeof entry.duration_ds === 'number' && entry.duration_ds > 0) out.set(name, entry.duration_ds);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Balance. Greedy longest-first onto the lightest shard. A test with no history gets the median of the known ones (a new test is as likely
// to be typical as to be quick), or `fallback` when nothing is known.

export function medianWeight(durations: Map<string, number>, fallback: number): number {
  if (durations.size === 0) return fallback;
  const sorted = [...durations.values()].sort((a, b) => a - b);
  return Math.max(sorted[Math.floor(sorted.length / 2)], 1);
}

export function packShards(names: string[], shardCount: number, durations: Map<string, number>, fallback: number): { shards: string[][]; loads: number[]; unknown: number } {
  const shards: string[][] = Array.from({ length: shardCount }, () => []);
  const loads = new Array<number>(shardCount).fill(0);
  const weight = medianWeight(durations, fallback);
  const w = (name: string) => durations.get(name) ?? weight;
  let unknown = 0;
  for (const name of names) if (!durations.has(name)) unknown++;
  for (const name of [...names].sort((a, b) => w(b) - w(a) || (a < b ? -1 : 1))) {
    let lightest = 0;
    for (let i = 1; i < shardCount; i++) if (loads[i] < loads[lightest]) lightest = i;
    shards[lightest].push(name);
    loads[lightest] += w(name);
  }
  return { shards, loads, unknown };
}
