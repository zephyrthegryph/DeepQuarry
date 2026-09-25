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

function git(...args: string[]): string {
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
$p = Get-Process -Id $args[0]
while ($p -and -not $p.HasExited) {
  $p.Refresh()
  Write-Output ("{0} {1} {2}" -f $p.PrivateMemorySize64, $p.WorkingSet64, $p.TotalProcessorTime.TotalSeconds)
  Start-Sleep -Milliseconds $args[1]
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
        // Arguments after -Command are not bound to $args; invoke a script block with them.
        ['-NoProfile', '-NonInteractive', '-Command', `& {${WINDOWS_SAMPLER}} ${pid} ${this.intervalMs}`],
        { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true },
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

export type Metric = { value: number; unit: string; better: 'lower' | 'higher' | 'none' };

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
  n: number;
  median: number;
  mean: number;
  min: number;
  max: number;
  stdev: number;
  values: number[];
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
};

export function statsOf(values: number[], unit: string, better: Metric['better']): MetricStats {
  const sorted = [...values].sort((a, b) => a - b);
  const n = sorted.length;
  const mean = n ? sorted.reduce((a, b) => a + b, 0) / n : 0;
  const median = n ? (n % 2 ? sorted[(n - 1) / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2) : 0;
  const variance = n > 1 ? sorted.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1) : 0;
  return {
    unit,
    better,
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
  const collected: Record<string, Record<string, { unit: string; better: Metric['better']; values: number[] }>> = {};
  const add = (scenario: string, name: string, metric: Metric) => {
    if (typeof metric?.value !== 'number' || !Number.isFinite(metric.value)) return;
    collected[scenario] ??= {};
    collected[scenario][name] ??= { unit: metric.unit, better: metric.better, values: [] };
    collected[scenario][name].values.push(metric.value);
  };
  for (const it of measured) {
    add('process', 'peak_private_mb', { value: it.process.peak_private_mb, unit: 'MB', better: 'lower' });
    add('process', 'final_private_mb', { value: it.process.final_private_mb, unit: 'MB', better: 'lower' });
    add('process', 'cpu_seconds', { value: it.process.cpu_seconds, unit: 's', better: 'lower' });
    add('process', 'wall_seconds', { value: it.process.wall_seconds, unit: 's', better: 'lower' });
    add('process', 'init_seconds', { value: it.init_seconds, unit: 's', better: 'lower' });
    add('process', 'runtimes', { value: it.total_runtimes, unit: 'runtimes', better: 'lower' });
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
      summary[scenario][name] = statsOf(m.values, m.unit, m.better);
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
  base: number;
  head: number;
  change_pct: number;
  noise_pct: number;
  verdict: 'regression' | 'improvement' | 'unchanged' | 'new' | 'removed';
};

/**
 * A change counts only if it exceeds both the threshold and twice the observed
 * run-to-run spread, so single noisy runs don't raise alarms.
 */
export function compareRuns(base: BenchRun, head: BenchRun, thresholdPct: number): Comparison[] {
  const rows: Comparison[] = [];
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
          scenario, metric, unit: s.unit,
          base: bs?.median ?? NaN, head: hs?.median ?? NaN,
          change_pct: NaN, noise_pct: NaN, verdict: bs ? 'removed' : 'new',
        });
        continue;
      }
      const denominator = Math.abs(bs.median) || 1e-9;
      const change = ((hs.median - bs.median) / denominator) * 100;
      const cv = (s: MetricStats) => (s.n > 1 && s.median ? (s.stdev / Math.abs(s.median)) * 100 : 0);
      const noise = 2 * Math.max(cv(bs), cv(hs));
      let verdict: Comparison['verdict'] = 'unchanged';
      const significant = Math.abs(change) > Math.max(thresholdPct, noise) && bs.median !== hs.median;
      if (significant && hs.better !== 'none') {
        const worse = hs.better === 'lower' ? change > 0 : change < 0;
        verdict = worse ? 'regression' : 'improvement';
      }
      rows.push({ scenario, metric, unit: hs.unit, base: bs.median, head: hs.median, change_pct: change, noise_pct: noise, verdict });
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
  const shown = onlyChanges ? rows.filter((r) => r.verdict !== 'unchanged') : rows;
  if (!shown.length) return 'No metric changed beyond the threshold.';
  const header = ['scenario', 'metric', 'base', 'head', 'change', 'noise', 'verdict'];
  const body = shown.map((r) => [
    r.scenario,
    r.metric,
    `${formatNumber(r.base)} ${r.unit}`,
    `${formatNumber(r.head)} ${r.unit}`,
    Number.isFinite(r.change_pct) ? `${r.change_pct >= 0 ? '+' : ''}${r.change_pct.toFixed(1)}%` : '-',
    Number.isFinite(r.noise_pct) ? `±${r.noise_pct.toFixed(1)}%` : '-',
    r.verdict,
  ]);
  const widths = header.map((h, i) => Math.max(h.length, ...body.map((row) => row[i].length)));
  const line = (cells: string[]) => cells.map((c, i) => c.padEnd(widths[i])).join('  ');
  return [line(header), line(widths.map((w) => '-'.repeat(w))), ...body.map(line)].join('\n');
}

// ---------------------------------------------------------------------------
// Locating stored runs

export const BENCH_RUNS_DIR = 'data/bench/runs';
export const TEST_RUNS_DIR = 'data/test-runs';

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
