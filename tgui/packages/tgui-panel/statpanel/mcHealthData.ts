/**
 * The logic of the MC Health panel (McHealth.tsx): the server's numbers (code/content/client/mc_health.dm) said in words.
 * Pure functions, tested in mcHealth.test.ts.
 */

export type PerfWindow = {
  samples: number;
  avg: number;
  p50: number;
  p95: number;
  p99: number;
  max: number;
  overruns: number;
  tps: number;
};

export type KernelSystem = {
  key: string;
  kind?: string;
  ms_per_s: number;
  p95_ms: number;
  overrun_share: number;
};

export type Outlier = {
  world_time: number;
  usage: number;
  overrun: number;
  cause?: string;
  maptick?: number;
  top_systems?: { key: string; ms: number }[];
  /** Where the tick went, in percent of a tick (Kernel.performance_tick_breakdown()). */
  breakdown?: { name: string; usage: number }[];
};

/** One recent tick: usage (% of the budget), its top system keys and their ms. */
export type RecentTick = [number, string[], number[]];

export type Histogram = {
  count: number;
  sum: number;
  max: number;
  bounds: number[];
  buckets: number[];
};

export type McHealthData = {
  tick_budget_ms: number;
  target_tps: number;
  current_usage: number;
  maptick: number;
  tidi: number;
  window_5s: PerfWindow;
  window_30s: PerfWindow;
  window_5m: PerfWindow;
  ticks: RecentTick[];
  outliers: Outlier[];
  kernel: {
    systems: KernelSystem[];
    byond_reserve?: number;
    input?: Record<string, number>;
    overruns?: number;
    ticks?: number;
  } | null;
  gc: {
    queued: number[];
    deleted_cleanly: number;
    forced: number;
    leaks: number;
  } | null;
  entities: {
    players: number;
    mobs: number;
    living: number;
    humans: number;
    machines: number;
    census: Census | null;
    previous: Census | null;
  };
  churn: Record<string, [string, number][]>;
  rust: Record<string, any> | null;
  /** The callbacks and redraws behind each busy system: list(source, kind, count, total ms, max ms), heaviest first. */
  attribution?: Record<string, [string, string, number, number, number][]>;
  /** The same for the systems ranked 5 to 8 (built on another send). */
  attribution_rest?: Record<string, [string, string, number, number, number][]>;
  runtime: Record<string, number>;
};

export type Census = {
  objects: number;
  turfs: number;
  areas: number;
  at: number;
  ms: number;
};

export type Verdict = {
  level: 'good' | 'average' | 'bad';
  label: string;
  why: string;
};

/** Healthy, Strained or Overloaded, and why, from the last 5 seconds and the overruns of the last 5 minutes. */
export function verdictOf(
  data: Pick<McHealthData, 'window_5s' | 'window_5m'>,
): Verdict {
  const now = data.window_5s;
  const overruns = data.window_5m?.overruns || 0;
  if (now.avg > 90 || now.p99 > 150 || overruns > 50) {
    return {
      level: 'bad',
      label: 'Overloaded',
      why: `Ticks use ${Math.round(now.avg)}% of the budget on average; ${overruns} overruns in 5 min.`,
    };
  }
  if (now.avg > 60 || now.p99 > 100 || overruns > 0) {
    return {
      level: 'average',
      label: 'Strained',
      why:
        overruns > 0
          ? `${overruns} overrun${overruns === 1 ? '' : 's'} in 5 min; the slowest 1% of ticks use ${Math.round(now.p99)}%.`
          : `Ticks use ${Math.round(now.avg)}% of the budget on average.`,
    };
  }
  return {
    level: 'good',
    label: 'Healthy',
    why: 'Ticks fit the budget; no overruns in 5 min.',
  };
}

/** The value below which `fraction` of the observations fall, from a histogram's buckets (the bucket's upper bound; the max past the last). */
export function histogramPercentile(
  h: Histogram | null | undefined,
  fraction: number,
): number | null {
  if (!h?.count) return null;
  const rank = Math.ceil(h.count * fraction);
  let seen = 0;
  for (let i = 0; i < h.buckets.length; i++) {
    seen += h.buckets[i];
    if (seen >= rank) return i < h.bounds.length ? h.bounds[i] : h.max;
  }
  return h.max;
}

/** Bytes as "512 KB", "2.0 GB". */
export function bytes(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = n;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value >= 100 || unit === 0 ? Math.round(value) : value.toFixed(1)} ${units[unit]}`;
}

/** A count with thousands separators. */
export function count(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return '-';
  return Math.round(n).toLocaleString('en-US');
}

/** Change per minute between two censuses (world time in deciseconds), or null without a previous one. */
export function perMinute(
  now: number,
  before: number | undefined,
  nowAt: number,
  beforeAt: number | undefined,
): number | null {
  if (before === undefined || beforeAt === undefined || nowAt <= beforeAt)
    return null;
  return ((now - before) / (nowAt - beforeAt)) * 600;
}

/** The kernel's systems, busiest first, with the share of the second each takes. */
export function systemsByCost(
  systems: KernelSystem[] | undefined,
): (KernelSystem & { share: number })[] {
  const list = (systems || []).slice().sort((a, b) => b.ms_per_s - a.ms_per_s);
  return list.map((s) => ({ ...s, share: s.ms_per_s / 1000 }));
}

/** The one-line summary of the overruns: the system in most of them, and how much of the time was over budget. */
export function overrunSummary(
  outliers: Outlier[],
  window5m: PerfWindow | undefined,
): string {
  if (!outliers.length) return 'No overruns recorded.';
  const seen: Record<string, number> = {};
  for (const o of outliers) {
    for (const s of o.top_systems?.slice(0, 1) || [])
      seen[s.key] = (seen[s.key] || 0) + 1;
  }
  const top = Object.entries(seen).sort((a, b) => b[1] - a[1])[0];
  const share = window5m?.samples
    ? Math.round((window5m.overruns / window5m.samples) * 1000) / 10
    : 0;
  return `${top ? `${top[0]} leads ${top[1]} of the last ${outliers.length} overruns` : `${outliers.length} recent overruns`}; ${share}% of ticks in 5 min were over budget.`;
}

/** Friendly names for the native frame's phases. */
export const PHASE_LABELS: Record<string, string> = {
  open: 'Start of frame',
  pace_stage: 'Copy inputs in',
  pace_step: 'Simulate',
  pace_apply: 'Write results back',
  stage_device_loop: 'Devices',
  stage_law_index: 'Find awake work',
  sched_evaluate: 'Scheduler: check',
  sched_step: 'Scheduler: run',
  pace_probes: 'Probes',
};

/** The native frame's phases as list(label, average microseconds per frame), largest first. */
export function framePhases(
  rust: Record<string, any> | null,
): [string, number][] {
  if (!rust) return [];
  const frames = Number(rust['frame.count']) || 0;
  if (!frames) return [];
  const out: [string, number][] = [];
  for (const name of Object.keys(rust)) {
    if (!name.startsWith('frame.us.')) continue;
    const phase = name.slice('frame.us.'.length);
    out.push([PHASE_LABELS[phase] || phase, Number(rust[name]) / frames]);
  }
  return out.sort((a, b) => b[1] - a[1]);
}

/** Native memory by area (alloc.<area>.current_bytes), largest first, the totals left out. */
export function nativeMemoryByArea(
  rust: Record<string, any> | null,
): [string, number][] {
  if (!rust) return [];
  const out: [string, number][] = [];
  for (const name of Object.keys(rust)) {
    const m = name.match(/^alloc\.([a-z_]+)\.current_bytes$/);
    if (!m || m[1] === 'heap' || m[1] === 'total') continue;
    out.push([m[1], Number(rust[name])]);
  }
  return out.sort((a, b) => b[1] - a[1]);
}

/** What the native world is doing: list(name, awake, stepped) for each law or field that has either. */
export function nativeWork(
  rust: Record<string, any> | null,
): [string, number, number][] {
  if (!rust) return [];
  const rows: Record<string, [number, number]> = {};
  for (const name of Object.keys(rust)) {
    const awake = name.match(/^world\.awake\.(.+)$/);
    const stepped = name.match(/^world\.stepped\.(.+)$/);
    const key = (awake || stepped)?.[1];
    if (!key) continue;
    const label = key
      .replace(/^field_/, '')
      .replace(/_(chunks|edges|touched)$/, '');
    rows[label] ||= [0, 0];
    rows[label][awake ? 0 : 1] += Number(rust[name]) || 0;
  }
  return Object.entries(rows)
    .filter(([, [a, s]]) => a || s)
    .map(([k, [a, s]]): [string, number, number] => [k, a, s])
    .sort((x, y) => y[2] - x[2] || y[1] - x[1]);
}

/** One consumer of a tick: its name and ms, `unknown` when nothing could be charged with it. */
export type TickPart = { name: string; ms: number; unknown?: boolean };

const byMs = (a: TickPart, b: TickPart) => b.ms - a.ms;

/** What an overrun's time went to, biggest first: the kernel's whole breakdown, with the engine's share split into its systems and the map send added. */
export function overrunParts(o: Outlier, budgetMs: number): TickPart[] {
  const toMs = (usage: number) => (usage / 100) * budgetMs;
  const parts: TickPart[] = [];
  const named = new Set((o.breakdown || []).map((b) => b.name));
  for (const { name, usage } of o.breakdown || []) {
    const ms = toMs(usage);
    if (name === 'Outside MC') {
      parts.push({ name: 'Before the kernel (verbs, input, BYOND)', ms });
    } else if (name === 'MC other') {
      parts.push({ name: 'Not attributed (kernel loop)', ms, unknown: true });
    } else if (name === 'engine') {
      let left = ms;
      for (const top of o.top_systems || []) {
        if (named.has(top.key) || left <= 0) continue;
        const taken = Math.min(top.ms, left);
        parts.push({ name: top.key, ms: taken });
        left -= taken;
      }
      if (left >= 0.05)
        parts.push({ name: 'Other engine work', ms: left, unknown: true });
    } else {
      parts.push({ name, ms });
    }
  }
  if (o.maptick) parts.push({ name: 'Map send (BYOND)', ms: toMs(o.maptick) });
  return parts.filter((part) => part.ms > 0).sort(byMs);
}

/** A recent tick's consumers, biggest first; the time its top systems do not explain is shown, not dropped. */
export function tickParts(tick: RecentTick, budgetMs: number): TickPart[] {
  const parts: TickPart[] = tick[1].map((name, i) => ({
    name,
    ms: tick[2][i] || 0,
  }));
  const rest = (tick[0] / 100) * budgetMs - parts.reduce((n, p) => n + p.ms, 0);
  if (rest >= 0.05)
    parts.push({ name: 'Everything else', ms: rest, unknown: true });
  return parts.sort(byMs);
}

/** The average tick by consumer, in ms per tick: the systems, and what the tick spent that no system was charged with. */
export function averageTickParts(
  systems: { key: string; ms_per_s: number }[],
  usagePercent: number,
  budgetMs: number,
  tps: number,
): TickPart[] {
  const perTick = tps > 0 ? tps : 1;
  const parts: TickPart[] = systems.map((s) => ({
    name: s.key,
    ms: s.ms_per_s / perTick,
  }));
  const rest =
    (usagePercent / 100) * budgetMs - parts.reduce((n, p) => n + p.ms, 0);
  if (rest >= 0.05)
    parts.push({ name: 'Not attributed', ms: rest, unknown: true });
  return parts.sort(byMs);
}
