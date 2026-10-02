/**
 * Benchmark and test-run bookkeeping for the `bench`, `bench-compare`,
 * `bench-report`, `test-repeat` and `test-baseline` targets.
 *
 * Everything is stored as plain JSON under data/ so it can be diffed, uploaded
 * as a CI artifact, or read by other tools:
 *   data/bench/runs/<id>.json      one file per benchmark invocation
 *   data/bench/report.html         generated history/comparison page
 *   data/test-runs/<id>.json       one file per unit-test run
 */

import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// ---------------------------------------------------------------------------
// Git / run identity

export type RunIdentity = {
  id: string;
  timestamp: string;
  commit: string;
  branch: string;
  dirty_files: number;
  host: string;
  platform: string;
};

export function git(...args: string[]): string {
  const result = spawnSync('git', args, { encoding: 'utf-8' });
  return result.status === 0 ? result.stdout.trim() : '';
}

export function runIdentity(label?: string | null): RunIdentity {
  const commit = git('rev-parse', '--short=10', 'HEAD') || 'unknown';
  const status = git('status', '--porcelain');
  const timestamp = new Date().toISOString();
  const stamp = timestamp.replace(/[-:]/g, '').replace(/\..*/, '');
  const suffix = label ? `_${label.replace(/[^A-Za-z0-9_-]/g, '-')}` : '';
  return {
    id: `${stamp}_${commit}${suffix}`,
    timestamp,
    commit,
    branch: git('rev-parse', '--abbrev-ref', 'HEAD') || 'unknown',
    dirty_files: status ? status.split(/\r?\n/).length : 0,
    host: process.env.COMPUTERNAME || process.env.HOSTNAME || 'unknown',
    platform: process.platform,
  };
}

export function writeJson(file: string, value: unknown): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 1)}\n`);
  fs.renameSync(temp, file);
}

export function readJson<T>(file: string): T {
  return JSON.parse(fs.readFileSync(file, 'utf-8')) as T;
}

// ---------------------------------------------------------------------------
// Process sampling. DM can't read its own memory use, so the runner samples
// DreamDaemon from outside and mirrors the latest reading into
// data/bench/process.json, which the world reads at each mark().

export type ProcessSample = {
  t: number; // seconds since sampling began
  private_mb: number;
  working_set_mb: number;
  cpu_seconds: number;
};

export type ProcessSummary = {
  samples: number;
  peak_private_mb: number;
  final_private_mb: number;
  peak_working_set_mb: number;
  cpu_seconds: number;
  wall_seconds: number;
};

const MB = 1024 * 1024;

// One long-lived PowerShell loop is far cheaper than spawning per sample.
const WINDOWS_SAMPLER = `
$ErrorActionPreference = 'SilentlyContinue'
$p = Get-Process -Id ([int]$env:DQ_BENCH_PID)
while ($p -and -not $p.HasExited) {
  $p.Refresh()
  Write-Output ("{0} {1} {2}" -f $p.PrivateMemorySize64, $p.WorkingSet64, $p.TotalProcessorTime.TotalSeconds)
  Start-Sleep -Milliseconds ([int]$env:DQ_BENCH_INTERVAL_MS)
}
`;

export class ProcessSampler {
  samples: ProcessSample[] = [];
  private started = Date.now();
  private stopFn: (() => void) | null = null;

  constructor(
    private liveFile: string,
    private intervalMs = 1000,
  ) {}

  start(pid: number): void {
    this.started = Date.now();
    if (process.platform === 'win32') {
      const child = spawn(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', WINDOWS_SAMPLER],
        {
          stdio: ['ignore', 'pipe', 'ignore'],
          windowsHide: true,
          env: { ...process.env, DQ_BENCH_PID: String(pid), DQ_BENCH_INTERVAL_MS: String(this.intervalMs) },
        },
      );
      let buffer = '';
      child.stdout.on('data', (chunk: Buffer) => {
        buffer += chunk.toString();
        const lines = buffer.split(/\r?\n/);
        buffer = lines.pop() ?? '';
        for (const line of lines) {
          const [priv, ws, cpu] = line.trim().split(/\s+/).map(Number);
          if (Number.isFinite(priv)) {
            this.record(priv / MB, ws / MB, cpu);
          }
        }
      });
      this.stopFn = () => child.kill();
    } else {
      const ticksPerSecond = 100;
      const timer = setInterval(() => {
        try {
          const status = fs.readFileSync(`/proc/${pid}/status`, 'utf-8');
          const rss = Number(/VmRSS:\s+(\d+)/.exec(status)?.[1] ?? 0) / 1024;
          const anon = Number(/RssAnon:\s+(\d+)/.exec(status)?.[1] ?? 0) / 1024;
          const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf-8').split(') ')[1].split(' ');
          const cpu = (Number(stat[11]) + Number(stat[12])) / ticksPerSecond;
          this.record(anon || rss, rss, cpu);
        } catch {
          // process gone
        }
      }, this.intervalMs);
      this.stopFn = () => clearInterval(timer);
    }
  }

  private record(privateMb: number, workingSetMb: number, cpuSeconds: number): void {
    const sample: ProcessSample = {
      t: (Date.now() - this.started) / 1000,
      private_mb: Math.round(privateMb * 10) / 10,
      working_set_mb: Math.round(workingSetMb * 10) / 10,
      cpu_seconds: Math.round(cpuSeconds * 100) / 100,
    };
    this.samples.push(sample);
    try {
      writeJson(this.liveFile, sample);
    } catch {
      // The world may be reading it; the next sample will land.
    }
  }

  stop(): ProcessSummary {
    this.stopFn?.();
    this.stopFn = null;
    const privates = this.samples.map((s) => s.private_mb);
    const last = this.samples[this.samples.length - 1];
    return {
      samples: this.samples.length,
      peak_private_mb: privates.length ? Math.max(...privates) : 0,
      final_private_mb: last?.private_mb ?? 0,
      peak_working_set_mb: this.samples.length
        ? Math.max(...this.samples.map((s) => s.working_set_mb))
        : 0,
      cpu_seconds: last?.cpu_seconds ?? 0,
      wall_seconds: (Date.now() - this.started) / 1000,
    };
  }
}

// ---------------------------------------------------------------------------
// Benchmark result documents

/**
 * `class` distinguishes load-independent counts (FFI calls, reactor wakes,
 * subsystem work-item counts, census/list counts, Rust heap bytes — the same
 * work happens regardless of how fast the machine gets through it) from
 * wall-clock/tick TIMING metrics, which this machine's other load visibly
 * moves. Absent (older stored runs) is treated as 'timing'. See
 * classOf()/loadSimilar() below and /datum/benchmark/proc/metric() in
 * code/modules/benchmarks/_benchmark.dm.
 */
export type MetricClass = 'count' | 'timing';
export type Metric = { value: number; unit: string; better: 'lower' | 'higher' | 'none'; class?: MetricClass };

export function classOf(metric: { class?: MetricClass }): MetricClass {
  return metric.class === 'count' ? 'count' : 'timing';
}

export type ScenarioResult = {
  id: string;
  status: string;
  error?: string;
  description?: string;
  duration_seconds?: number;
  runtimes?: number;
  metrics: Record<string, Metric>;
  details?: Record<string, unknown>;
  phases?: unknown[];
};

/** What the world writes to data/bench/scenarios.json. */
export type WorldBenchDocument = {
  byond_version: string;
  map: string;
  world: Record<string, number>;
  init_seconds: number;
  subsystem_init_ms: Record<string, number>;
  total_runtimes: number;
  scenarios: Record<string, ScenarioResult>;
};

export type BenchIteration = WorldBenchDocument & {
  iteration: number;
  warmup: boolean;
  process: ProcessSummary;
  process_samples: ProcessSample[];
  profiles?: string[];
};

export type MetricStats = {
  unit: string;
  better: Metric['better'];
  class: MetricClass;
  n: number;
  median: number;
  mean: number;
  min: number;
  max: number;
  stdev: number;
  values: number[];
};

/**
 * Load conditions this run was taken under, sampled by LoadSampler while the
 * world(s) ran. `exclusive` means it ran under the `bench --exclusive` lock
 * with the DreamDaemon slots drained first (see BenchExclusiveLock /
 * ddSlotBaseDir()) — the closest thing to a quiet machine this tooling can
 * arrange. `other_dreamdaemon`/`other_dm`/`cargo_rustc` are averaged process
 * counts (this run's own DreamDaemon is excluded); `cpu_percent` is the
 * averaged system-wide CPU load sampled during the run.
 */
export type LoadContext = {
  machine_id: string;
  exclusive: boolean;
  other_dreamdaemon: number;
  other_dm: number;
  cargo_rustc: number;
  cpu_percent: number;
};

export type BenchRun = RunIdentity & {
  kind: 'bench';
  label: string | null;
  map: string;
  defines: string[];
  scenarios_requested: string[];
  args: string[];
  iterations: BenchIteration[];
  /** Per scenario, per metric, over the non-warmup iterations. */
  summary: Record<string, Record<string, MetricStats>>;
  failures: string[];
  load: LoadContext;
};

export function statsOf(values: number[], unit: string, better: Metric['better'], metricClass: MetricClass = 'timing'): MetricStats {
  const sorted = [...values].sort((a, b) => a - b);
  const n = sorted.length;
  const mean = n ? sorted.reduce((a, b) => a + b, 0) / n : 0;
  const median = n ? (n % 2 ? sorted[(n - 1) / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2) : 0;
  const variance = n > 1 ? sorted.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1) : 0;
  return {
    unit,
    better,
    class: metricClass,
    n,
    median,
    mean,
    min: sorted[0] ?? 0,
    max: sorted[n - 1] ?? 0,
    stdev: Math.sqrt(variance),
    values,
  };
}

/** Process-level numbers become a synthetic `process` scenario. */
export function summarize(iterations: BenchIteration[]): BenchRun['summary'] {
  const measured = iterations.filter((it) => !it.warmup);
  const collected: Record<string, Record<string, { unit: string; better: Metric['better']; class: MetricClass; values: number[] }>> = {};
  const add = (scenario: string, name: string, metric: Metric) => {
    if (typeof metric?.value !== 'number' || !Number.isFinite(metric.value)) return;
    collected[scenario] ??= {};
    collected[scenario][name] ??= { unit: metric.unit, better: metric.better, class: classOf(metric), values: [] };
    collected[scenario][name].values.push(metric.value);
  };
  for (const it of measured) {
    // Process-level readings are all wall-clock/RSS numbers this machine's
    // other load visibly moves, except the runtime-exception count, which
    // reflects game logic, not speed.
    add('process', 'peak_private_mb', { value: it.process.peak_private_mb, unit: 'MB', better: 'lower' });
    add('process', 'final_private_mb', { value: it.process.final_private_mb, unit: 'MB', better: 'lower' });
    add('process', 'cpu_seconds', { value: it.process.cpu_seconds, unit: 's', better: 'lower' });
    add('process', 'wall_seconds', { value: it.process.wall_seconds, unit: 's', better: 'lower' });
    add('process', 'init_seconds', { value: it.init_seconds, unit: 's', better: 'lower' });
    add('process', 'runtimes', { value: it.total_runtimes, unit: 'runtimes', better: 'lower', class: 'count' });
    for (const [scenarioId, scenario] of Object.entries(it.scenarios ?? {})) {
      for (const [name, metric] of Object.entries(scenario.metrics ?? {})) {
        add(scenarioId, name, metric);
      }
    }
  }
  const summary: BenchRun['summary'] = {};
  for (const [scenario, metrics] of Object.entries(collected)) {
    summary[scenario] = {};
    for (const [name, m] of Object.entries(metrics)) {
      summary[scenario][name] = statsOf(m.values, m.unit, m.better, m.class);
    }
  }
  return summary;
}

// ---------------------------------------------------------------------------
// Comparison

export type Comparison = {
  scenario: string;
  metric: string;
  unit: string;
  class: MetricClass;
  base: number;
  head: number;
  change_pct: number;
  noise_pct: number;
  verdict: 'regression' | 'improvement' | 'unchanged' | 'new' | 'removed' | 'not_comparable';
  /** Set when a gate (GATES) decided the verdict: what it requires. */
  gate?: string;
};

/**
 * Metrics that gate a change however small the generic threshold would let it through. Each names a metric
 * family and what may not happen to it:
 *  - `no_rise`: the median may not rise (beyond the runs' own noise and `absTolerance`, the resolution below which
 *    a difference means nothing);
 *  - `flag_pct`: a rise of more than `pct` percent is flagged.
 * Only `lower is better` metrics gate. A timing metric still needs both runs to be load-similar to be compared at
 * all (compareRuns()). The metric names come from code/modules/benchmarks/kernel_metrics.dm.
 */
export type Gate = {
  pattern: RegExp;
  label: string;
  rule: 'no_rise' | 'flag_pct';
  pct?: number;
  absTolerance?: number;
};

export const GATES: Gate[] = [
  // Input latency: the wait of a click or queued verb, from the synthetic load. 0.05 ms is the histogram's first
  // bin edge (0.02 ms) and change: below it nothing waited.
  { pattern: /^input_p99$/, label: 'input_p99 must not rise', rule: 'no_rise', absTolerance: 0.05 },
  { pattern: /^input_p99_ticks$/, label: 'input_p99 must not rise', rule: 'no_rise', absTolerance: 0.001 },
  // A behaviour whose slot started later than its max interval, per system and in total.
  { pattern: /(^|\.)breaches$/, label: 'breaches must not rise', rule: 'no_rise' },
  // A system's p99 ms per tick rising by more than a fifth is named.
  { pattern: /^system\..+\.p99_ms$/, label: 'system p99_ms rose over 20%', rule: 'flag_pct', pct: 20, absTolerance: 0.05 },
];

/** The gate covering a metric name (a scenario-level or a windowed one: `idle_input_p99`), if any. */
export function gateFor(metric: string): Gate | undefined {
  return GATES.find((gate) => gate.pattern.test(metric));
}

/**
 * True when two runs' machine load is close enough that a TIMING metric
 * between them means something. Both taken under the exclusive bench lock
 * (see BenchExclusiveLock) always counts as similar — that's the point of
 * the lock. Otherwise, similar means: same exclusivity, system CPU within 20
 * points, and no more than one extra concurrent DreamDaemon/dm/cargo/rustc
 * process apiece (and at most two total), which is noisy but not "someone is
 * running a full build next to this benchmark."
 */
export function loadSimilar(a: LoadContext | undefined, b: LoadContext | undefined): boolean {
  if (!a || !b) return false;
  if (a.exclusive && b.exclusive) return true;
  if (a.exclusive !== b.exclusive) return false;
  const loadOf = (l: LoadContext) => l.other_dreamdaemon + l.other_dm + l.cargo_rustc;
  const loadA = loadOf(a);
  const loadB = loadOf(b);
  return Math.abs(a.cpu_percent - b.cpu_percent) <= 20 && Math.abs(loadA - loadB) <= 1 && loadA <= 2 && loadB <= 2;
}

/**
 * A change counts only if it exceeds both the threshold and twice the
 * observed run-to-run spread, so single noisy runs don't raise alarms. COUNT
 * metrics (see MetricClass) always compare, with a tight threshold, since
 * they don't move with machine load. TIMING metrics only compare when both
 * runs' recorded LoadContext (see BenchRun.load) are load-similar; otherwise
 * they're reported 'not_comparable (load)' rather than silently skipped.
 */
export function compareRuns(base: BenchRun, head: BenchRun, thresholdPct: number): Comparison[] {
  const rows: Comparison[] = [];
  const timingComparable = loadSimilar(base.load, head.load);
  const scenarios = new Set([...Object.keys(base.summary), ...Object.keys(head.summary)]);
  for (const scenario of scenarios) {
    const b = base.summary[scenario] ?? {};
    const h = head.summary[scenario] ?? {};
    for (const metric of new Set([...Object.keys(b), ...Object.keys(h)])) {
      const bs = b[metric];
      const hs = h[metric];
      if (!bs || !hs) {
        const s = (bs ?? hs) as MetricStats;
        rows.push({
          scenario, metric, unit: s.unit, class: s.class,
          base: bs?.median ?? NaN, head: hs?.median ?? NaN,
          change_pct: NaN, noise_pct: NaN, verdict: bs ? 'removed' : 'new',
        });
        continue;
      }
      const metricClass = classOf(hs);
      if (metricClass === 'timing' && !timingComparable) {
        rows.push({
          scenario, metric, unit: hs.unit, class: metricClass,
          base: bs.median, head: hs.median, change_pct: NaN, noise_pct: NaN, verdict: 'not_comparable',
        });
        continue;
      }
      const effectiveThreshold = metricClass === 'count' ? Math.min(thresholdPct, 1) : thresholdPct;
      const denominator = Math.abs(bs.median) || 1e-9;
      const change = ((hs.median - bs.median) / denominator) * 100;
      const cv = (s: MetricStats) => (s.n > 1 && s.median ? (s.stdev / Math.abs(s.median)) * 100 : 0);
      const noise = 2 * Math.max(cv(bs), cv(hs));
      let verdict: Comparison['verdict'] = 'unchanged';
      const significant = Math.abs(change) > Math.max(effectiveThreshold, noise) && bs.median !== hs.median;
      if (significant && hs.better !== 'none') {
        const worse = hs.better === 'lower' ? change > 0 : change < 0;
        verdict = worse ? 'regression' : 'improvement';
      }
      // A gate overrides the generic threshold: a rise it forbids is a regression however small.
      let gateLabel: string | undefined;
      const gate = hs.better === 'lower' ? gateFor(metric) : undefined;
      if (gate) {
        const rise = hs.median - bs.median;
        // Below the metric's resolution a difference in either direction is noise, whatever the generic rule said.
        if (gate.absTolerance !== undefined && Math.abs(rise) <= gate.absTolerance) verdict = 'unchanged';
        const beyondNoise = change > noise;
        const beyondFloor = rise > (gate.absTolerance ?? 0);
        const beyondPct = gate.rule === 'flag_pct' ? change > (gate.pct ?? 0) : true;
        if (rise > 0 && beyondNoise && beyondFloor && beyondPct) {
          verdict = 'regression';
          gateLabel = gate.label;
        }
      }
      rows.push({
        scenario, metric, unit: hs.unit, class: metricClass, base: bs.median, head: hs.median,
        change_pct: change, noise_pct: noise, verdict, ...(gateLabel ? { gate: gateLabel } : {}),
      });
    }
  }
  return rows;
}

export function formatNumber(value: number): string {
  if (!Number.isFinite(value)) return '-';
  const abs = Math.abs(value);
  if (abs >= 1000) return value.toFixed(0);
  if (abs >= 10) return value.toFixed(1);
  return value.toFixed(2);
}

export function formatComparison(rows: Comparison[], onlyChanges = false): string {
  const shown = onlyChanges ? rows.filter((r) => r.verdict !== 'unchanged' && r.verdict !== 'not_comparable') : rows;
  if (!shown.length) return 'No metric changed beyond the threshold.';
  const header = ['scenario', 'metric', 'class', 'base', 'head', 'change', 'noise', 'verdict'];
  const body = shown.map((r) => [
    r.scenario,
    r.metric,
    r.class,
    `${formatNumber(r.base)} ${r.unit}`,
    `${formatNumber(r.head)} ${r.unit}`,
    Number.isFinite(r.change_pct) ? `${r.change_pct >= 0 ? '+' : ''}${r.change_pct.toFixed(1)}%` : '-',
    Number.isFinite(r.noise_pct) ? `±${r.noise_pct.toFixed(1)}%` : '-',
    r.verdict === 'not_comparable' ? 'not comparable (load)' : r.gate ? `${r.verdict} (gate: ${r.gate})` : r.verdict,
  ].map((cell) => String(cell ?? '-'))); // a metric missing from one side (class, verdict) prints '-'
  const widths = header.map((h, i) => Math.max(h.length, ...body.map((row) => row[i].length)));
  const line = (cells: string[]) => cells.map((c, i) => c.padEnd(widths[i])).join('  ');
  return [line(header), line(widths.map((w) => '-'.repeat(w))), ...body.map(line)].join('\n');
}

// ---------------------------------------------------------------------------
// Machine load sampling. Mirrors ProcessSampler's approach (one long-lived
// PowerShell loop on Windows) so a benchmark run knows how contended the
// machine was, which compareRuns()/loadSimilar() use to decide whether
// TIMING metrics are even worth comparing.

const WINDOWS_LOAD_SAMPLER = `
$ErrorActionPreference = 'SilentlyContinue'
while ($true) {
  $procs = Get-Process -ErrorAction SilentlyContinue
  $dd = ($procs | Where-Object { $_.ProcessName -ieq 'dreamdaemon' }).Count
  $dmc = ($procs | Where-Object { $_.ProcessName -ieq 'dm' }).Count
  $cr = ($procs | Where-Object { $_.ProcessName -ieq 'cargo' -or $_.ProcessName -ieq 'rustc' }).Count
  $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average
  Write-Output ("{0} {1} {2} {3}" -f $dd, $dmc, $cr, $cpu)
  Start-Sleep -Milliseconds $args[0]
}
`;

type LoadSample = { dd: number; dmc: number; cr: number; cpu: number };

export class LoadSampler {
  private samples: LoadSample[] = [];
  private child: ReturnType<typeof spawn> | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(private intervalMs = 3000) {}

  start(): void {
    if (process.platform === 'win32') {
      const child = spawn(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', WINDOWS_LOAD_SAMPLER, String(this.intervalMs)],
        { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true },
      );
      let buffer = '';
      child.stdout.on('data', (chunk: Buffer) => {
        buffer += chunk.toString();
        const lines = buffer.split(/\r?\n/);
        buffer = lines.pop() ?? '';
        for (const line of lines) {
          const [dd, dmc, cr, cpu] = line.trim().split(/\s+/).map(Number);
          if (Number.isFinite(dd)) this.samples.push({ dd, dmc, cr, cpu: Number.isFinite(cpu) ? cpu : 0 });
        }
      });
      this.child = child;
    } else {
      const sampleOnce = () => {
        try {
          const psOut = spawnSync('ps', ['-eo', 'comm='], { encoding: 'utf-8' }).stdout ?? '';
          const names = psOut.split(/\r?\n/).map((n) => n.trim().toLowerCase());
          const dd = names.filter((n) => n.includes('dreamdaemon')).length;
          const dmc = names.filter((n) => n === 'dm' || n === 'dreammaker').length;
          const cr = names.filter((n) => n === 'cargo' || n === 'rustc').length;
          const cpu = (os.loadavg()[0] / Math.max(os.cpus().length, 1)) * 100;
          this.samples.push({ dd, dmc, cr, cpu });
        } catch {
          // a missed sample doesn't matter; the average absorbs it
        }
      };
      sampleOnce();
      this.timer = setInterval(sampleOnce, this.intervalMs);
    }
  }

  /**
   * Averages the samples into a LoadContext. `ownDreamDaemonRunning` subtracts
   * one from the observed DreamDaemon count for the world this run itself
   * booted, so `other_dreamdaemon` means "besides mine".
   */
  stop(ownDreamDaemonRunning: boolean, exclusive: boolean): LoadContext {
    this.child?.kill();
    this.child = null;
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    const avg = (f: (s: LoadSample) => number) =>
      this.samples.length ? this.samples.reduce((a, s) => a + f(s), 0) / this.samples.length : 0;
    return {
      machine_id: process.env.COMPUTERNAME || process.env.HOSTNAME || os.hostname() || 'unknown',
      exclusive,
      other_dreamdaemon: Math.max(0, Math.round(avg((s) => s.dd)) - (ownDreamDaemonRunning ? 1 : 0)),
      other_dm: Math.round(avg((s) => s.dmc)),
      cargo_rustc: Math.round(avg((s) => s.cr)),
      cpu_percent: Math.round(avg((s) => s.cpu) * 10) / 10,
    };
  }
}

// ---------------------------------------------------------------------------
// Exclusive bench slot (`bench --exclusive`). Takes a machine-wide mkdir lock
// so other exclusive runs queue behind it, then waits for the DreamDaemon
// slot directories (tools/ci/dd-slot.sh) to drain before returning, so the
// benchmark gets as close to a quiet machine as this tooling can arrange.
// The lock self-expires after `maxHoldMs` so a stuck or killed holder can't
// starve other agents forever.

function readIntFile(file: string): number {
  try {
    return Number(fs.readFileSync(file, 'utf-8').trim()) || 0;
  } catch {
    return 0;
  }
}

function processAlive(pid: number): boolean {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export type ExclusiveLock = { release(): void };

/** Acquires the exclusive bench lock, waiting out any other holder (including a stale one). */
export async function acquireBenchExclusiveLock(maxHoldMs = 20 * 60 * 1000, pollMs = 5000): Promise<ExclusiveLock> {
  const dir = benchExclusiveLockDir();
  // The lock dir's parent (e.g. DQ_BENCH_STORE) may not exist yet on a fresh
  // machine/store -- create it up front so the mkdirSync below fails with
  // EEXIST (contended, the case we want to detect and wait out) rather than
  // ENOENT (missing parent, which looked identical to contention and would
  // spin forever: "stale" was always true for a nonexistent dir, so it kept
  // trying to rmSync a directory that was never created and retrying immediately).
  fs.mkdirSync(path.dirname(dir), { recursive: true });
  for (;;) {
    try {
      fs.mkdirSync(dir, { recursive: false });
      break;
    } catch {
      const pid = readIntFile(path.join(dir, 'pid'));
      const started = readIntFile(path.join(dir, 'started'));
      const stale = !processAlive(pid) || (started > 0 && Date.now() - started > maxHoldMs);
      if (stale) {
        try {
          fs.rmSync(dir, { recursive: true, force: true });
        } catch {
          // lost the race to reclaim it; loop and retry
        }
        continue;
      }
      await sleep(pollMs);
    }
  }
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'pid'), String(process.pid));
  fs.writeFileSync(path.join(dir, 'started'), String(Date.now()));
  let released = false;
  return {
    release: () => {
      if (released) return;
      released = true;
      try {
        fs.rmSync(dir, { recursive: true, force: true });
      } catch {
        // best effort; a stale lock still self-expires via maxHoldMs
      }
    },
  };
}

/**
 * Waits until every DreamDaemon slot directory is empty (or stale-owned), or
 * the timeout elapses. Returns whether it drained.
 *
 * When this process is itself running inside a dd-slot.sh-held slot
 * (DQ_DD_SLOT_HELD=1, set by dd-slot.sh around "$@"), that slot's directory
 * never looks empty -- it's occupied by the wrapper's own pid for the whole
 * invocation -- so waiting on it would just burn the full timeout every
 * time. dd-slot.sh already bounds machine-wide DreamDaemon concurrency in
 * that case, so skip the extra wait rather than pay for a drain that can't
 * happen.
 */
export async function waitForDreamDaemonsToDrain(timeoutMs = 5 * 60 * 1000, pollMs = 5000, log: (msg: string) => void = () => {}): Promise<boolean> {
  if (process.env.DQ_DD_SLOT_HELD === '1') return true;
  const base = ddSlotBaseDir();
  const deadline = Date.now() + timeoutMs;
  let announced = false;
  for (;;) {
    let busy = false;
    for (let i = 1; i <= 5; i++) {
      const dir = `${base}${i}`;
      const pidFile = path.join(dir, 'pid');
      if (!fs.existsSync(pidFile)) continue;
      const pid = readIntFile(pidFile);
      if (processAlive(pid)) {
        busy = true;
      } else {
        try {
          fs.rmSync(dir, { recursive: true, force: true });
        } catch {
          // another process is reclaiming it too; fine either way
        }
      }
    }
    if (!busy) return true;
    if (!announced) {
      log('Waiting for other DreamDaemon runs to drain before starting the exclusive benchmark...');
      announced = true;
    }
    if (Date.now() > deadline) return false;
    await sleep(pollMs);
  }
}

// ---------------------------------------------------------------------------
// Locating stored runs

export const BENCH_RUNS_DIR = 'data/bench/runs';
export const TEST_RUNS_DIR = 'data/test-runs';

/**
 * Benchmark runs are per-worktree by default (data/ is gitignored and lives
 * inside each worktree), so a branch worktree has no access to a master
 * baseline unless it re-runs one itself. Setting DQ_BENCH_STORE to a
 * directory outside any worktree (e.g. a sibling of the checkouts) turns
 * runs/, the exclusive-bench lock and the DreamDaemon slot directory it looks
 * for into shared, machine-wide state that every worktree on that machine can
 * read and write. Nothing here hardcodes a path — an unset DQ_BENCH_STORE
 * just falls back to the old per-worktree data/bench/runs behaviour.
 */
export function benchStoreDir(): string | null {
  return process.env.DQ_BENCH_STORE || null;
}

export function benchRunsDir(): string {
  const store = benchStoreDir();
  return store ? path.join(store, 'runs') : BENCH_RUNS_DIR;
}

/** Where the `bench --exclusive` lock directory lives (see BenchExclusiveLock). */
export function benchExclusiveLockDir(): string {
  return process.env.DQ_BENCH_EXCLUSIVE_LOCK || path.join(benchStoreDir() || 'data/bench', '.dq-bench-exclusive');
}

/**
 * Base path of the machine-wide DreamDaemon slot directories that
 * tools/ci/dd-slot.sh (and the scratchpad copy agents use) hand out as
 * `${base}1` .. `${base}5`. Configurable so the shared-store layout isn't
 * assumed; defaults to a sibling of the bench store so the default
 * DQ_BENCH_STORE=E:/projects/.dq-bench pairs with the slots agents already
 * use at E:/projects/.dq-dd-slot-N.
 */
export function ddSlotBaseDir(): string {
  if (process.env.DQ_DD_SLOT_BASE) return process.env.DQ_DD_SLOT_BASE;
  const store = benchStoreDir();
  const parent = store ? path.dirname(store) : path.resolve('data/bench');
  return path.join(parent, '.dq-dd-slot-');
}

export function listRuns(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => path.join(dir, f));
}

/**
 * Resolves `latest`, `previous`, a commit prefix, a run id prefix or a path to
 * a stored run file.
 */
export function resolveRun(dir: string, ref: string): string {
  if (fs.existsSync(ref)) return ref;
  const runs = listRuns(dir);
  if (!runs.length) throw new Error(`No stored runs in ${dir}.`);
  if (ref === 'latest') return runs[runs.length - 1];
  if (ref === 'previous') {
    if (runs.length < 2) throw new Error(`Only one run stored in ${dir}.`);
    return runs[runs.length - 2];
  }
  const matches = runs.filter((file) => {
    const name = path.basename(file);
    return name.startsWith(ref) || name.split('_')[1]?.startsWith(ref);
  });
  if (!matches.length) throw new Error(`No stored run matches '${ref}' in ${dir}.`);
  return matches[matches.length - 1];
}

// ---------------------------------------------------------------------------
// Baseline lookup: the master ancestor to compare a branch bench against.

export type BaselineLookup = { file: string; run: BenchRun; commit: string; isMergeBase: boolean };

/**
 * Finds the stored bench run (in the shared store, benchRunsDir()) for the
 * given map that's closest to `git merge-base HEAD master` — the merge-base
 * commit itself if a run was stored for it (see the `bench-baseline` target),
 * else the nearest master ancestor of it that has one. Returns null if
 * there's no merge-base (e.g. not on a branch off master) or no matching run
 * was found within the walked history.
 */
export function findBaselineRun(map: string, opts: { label?: string | null; historyDepth?: number } = {}): BaselineLookup | null {
  const mergeBase = git('merge-base', 'HEAD', 'master');
  if (!mergeBase) return null;
  const depth = opts.historyDepth ?? 1000;
  const ancestors = git('log', '--format=%H', `-${depth}`, mergeBase)
    .split(/\r?\n/)
    .filter(Boolean);
  if (!ancestors.length) return null;
  const dir = benchRunsDir();
  const files = listRuns(dir);
  if (!files.length) return null;
  const runs = files.map((file) => ({ file, run: readJson<BenchRun>(file) }));
  for (const fullHash of ancestors) {
    const shortHash = fullHash.slice(0, 10);
    const matches = runs.filter(
      (r) => r.run.commit === shortHash && r.run.map === map && (opts.label === undefined || r.run.label === opts.label),
    );
    if (matches.length) {
      const chosen = matches[matches.length - 1];
      return { file: chosen.file, run: chosen.run, commit: shortHash, isMergeBase: shortHash === mergeBase.slice(0, 10) };
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Unit-test run records

export type UnitTestEntry = {
  status: number;
  message?: string;
  name: string;
  duration_ds?: number;
  runtimes?: number;
  ticks?: { samples: number; overruns: number; max: number };
};

export type TestRun = RunIdentity & {
  kind: 'test';
  label: string | null;
  defines: string[];
  clean: boolean;
  duration_seconds: number;
  counts: { passed: number; failed: number; skipped: number };
  failed: string[];
  tests: Record<string, UnitTestEntry>;
};

export function testRunRecord(
  identity: RunIdentity,
  label: string | null,
  defines: string[],
  clean: boolean,
  durationSeconds: number,
  results: Record<string, UnitTestEntry>,
): TestRun {
  const counts = { passed: 0, failed: 0, skipped: 0 };
  const failed: string[] = [];
  for (const [name, result] of Object.entries(results)) {
    if (result.status === 0) counts.passed++;
    else if (result.status === 1) {
      counts.failed++;
      failed.push(name);
    } else counts.skipped++;
  }
  return {
    ...identity,
    kind: 'test',
    label,
    defines,
    clean,
    duration_seconds: durationSeconds,
    counts,
    failed: failed.sort(),
    tests: results,
  };
}

/** Slowest tests and tests that overran the tick, for the post-run summary. */
export function testHotspots(results: Record<string, UnitTestEntry>, top = 10): string {
  const entries = Object.entries(results);
  const slow = entries
    .filter(([, r]) => r.duration_ds)
    .sort((a, b) => (b[1].duration_ds ?? 0) - (a[1].duration_ds ?? 0))
    .slice(0, top);
  const overran = entries
    .filter(([, r]) => (r.ticks?.overruns ?? 0) > 0)
    .sort((a, b) => (b[1].ticks?.overruns ?? 0) - (a[1].ticks?.overruns ?? 0))
    .slice(0, top);
  const noisy = entries.filter(([, r]) => (r.runtimes ?? 0) > 0);
  const short = (name: string) => name.replace('/datum/unit_test/', '');
  const lines = ['Slowest tests:'];
  for (const [name, r] of slow) lines.push(`  ${((r.duration_ds ?? 0) / 10).toFixed(1).padStart(7)}s  ${short(name)}`);
  if (overran.length) {
    lines.push('Tests that overran the tick (usage > 100%):');
    for (const [name, r] of overran) {
      lines.push(`  ${String(r.ticks?.overruns).padStart(5)} of ${r.ticks?.samples} ticks, worst ${Math.round(r.ticks?.max ?? 0)}%  ${short(name)}`);
    }
  }
  if (noisy.length) {
    lines.push('Tests that raised runtimes:');
    for (const [name, r] of noisy) lines.push(`  ${String(r.runtimes).padStart(5)}  ${short(name)}`);
  }
  return lines.join('\n');
}
