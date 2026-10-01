// JSON endpoints behind /api. Every handler takes the parsed query and returns plain data.

import { config } from './config';
import { db, placeholders, query } from './db';
import { summarizeRound } from './maintenance';
import { median, type Summary, summarize } from './stats';

type Key = {
  id: number;
  name: string;
  category: string;
  subcategory: string;
  unit: string;
};
export type KeyStats = Key & Summary;

const num = (v: unknown, fallback: number) =>
  v === null || v === undefined || v === '' || Number.isNaN(Number(v))
    ? fallback
    : Number(v);

async function keysById(): Promise<Map<number, Key>> {
  const rows =
    (await db`SELECT id, name, category, subcategory, unit FROM metric_key`) as Key[];
  return new Map(rows.map((k) => [k.id, k]));
}

/** Per-metric summary of a round: its rollup if it has one, else computed from raw samples. */
export async function roundStats(
  roundId: number,
): Promise<Map<string, KeyStats>> {
  const keys = await keysById();
  const rolled =
    (await db`SELECT key_id, n, mean, min, p50, p95, p99, max FROM metric_round WHERE round_id = ${roundId}`) as (Summary & {
      key_id: number;
    })[];
  const out = new Map<string, KeyStats>();
  if (rolled.length) {
    for (const r of rolled) {
      const k = keys.get(r.key_id);
      if (k)
        out.set(k.name, {
          ...k,
          n: r.n,
          mean: r.mean,
          min: r.min,
          p50: r.p50,
          p95: r.p95,
          p99: r.p99,
          max: r.max,
        });
    }
    return out;
  }
  for (const [keyId, s] of await summarizeRound(roundId)) {
    const k = keys.get(keyId);
    if (k) out.set(k.name, { ...k, ...s });
  }
  return out;
}

/** Previous rounds' rollups of the given metrics, for baselines: name -> [values of `stat`]. */
async function baselineValues(
  roundId: number,
  names: string[],
  stat: keyof Summary,
): Promise<Map<string, number[]>> {
  const out = new Map<string, number[]>();
  if (!names.length) return out;
  const column = ['mean', 'min', 'p50', 'p95', 'p99', 'max'].includes(stat)
    ? stat
    : 'p95';
  const rounds = await query<{ round_id: number }>(
    `SELECT DISTINCT round_id FROM metric_round WHERE round_id < ? ORDER BY round_id DESC LIMIT ?`,
    [roundId, config.baselineRounds],
  );
  if (!rounds.length) return out;
  const rows = await query<{ name: string; v: number }>(
    `SELECT k.name, r.${column} AS v FROM metric_round r JOIN metric_key k ON k.id = r.key_id
		 WHERE r.round_id IN (${placeholders(rounds.length)}) AND k.name IN (${placeholders(names.length)})`,
    [...rounds.map((r) => r.round_id), ...names],
  );
  for (const row of rows) {
    const list = out.get(row.name) ?? [];
    if (!out.has(row.name)) out.set(row.name, list);
    list.push(row.v);
  }
  return out;
}

/** The smallest change worth flagging for a unit, so tiny absolute numbers don't read as spikes. */
function minDelta(unit: string): number {
  switch (unit) {
    case '%':
      return 3;
    case 'ms':
      return 0.5;
    case 'ms/s':
      return 2;
    default:
      return 1;
  }
}

type Flagged = KeyStats & {
  value: number;
  baseline: number | null;
  ratio: number | null;
  outlier: boolean;
  baseline_rounds: number;
};

function flag(
  stats: KeyStats,
  stat: keyof Summary,
  baseline: number[] | undefined,
): Flagged {
  const value = stats[stat] as number;
  const base = baseline?.length ? median(baseline) : null;
  const ratio = base !== null && base > 0 ? value / base : null;
  // Outlier: well above its own history, by a margin that matters for its unit, with enough history to judge.
  const outlier =
    base !== null &&
    (baseline?.length ?? 0) >= 3 &&
    value - base >= minDelta(stats.unit) &&
    (ratio === null || ratio >= 1.5);
  return {
    ...stats,
    value,
    baseline: base,
    ratio,
    outlier,
    baseline_rounds: baseline?.length ?? 0,
  };
}

// ---------------------------------------------------------------- rounds

/** A gap between samples this long means the server stopped sampling: it was frozen (or down). */
const STALL_SECONDS = 30;

/** Periods in a round when the world stopped sampling (gaps in the every-10 s server/cpu metric). */
export async function stallsFor(roundId: number) {
  const rows = await query<{ ts: Date }>(
    `SELECT s.ts FROM metric_sample s JOIN metric_key k ON k.id = s.key_id WHERE s.round_id = ? AND k.name = 'server/cpu' ORDER BY s.t`,
    [roundId],
  );
  const out: { from: Date; to: Date; seconds: number }[] = [];
  for (let i = 1; i < rows.length; i++) {
    const gap =
      (new Date(rows[i].ts).getTime() - new Date(rows[i - 1].ts).getTime()) /
      1000;
    if (gap >= STALL_SECONDS)
      out.push({ from: rows[i - 1].ts, to: rows[i].ts, seconds: gap });
  }
  return out;
}

export async function stalls(q: URLSearchParams) {
  return stallsFor(num(q.get('round'), 0));
}

async function roundEvents(roundIds: number[]) {
  if (!roundIds.length) return [];
  return query<{
    round_id: number;
    category: string;
    payload: string | null;
    ts: Date;
  }>(
    `SELECT round_id, category, payload, ts FROM metric_event WHERE kind = 'round' AND round_id IN (${placeholders(roundIds.length)}) ORDER BY ts`,
    roundIds,
  );
}

export async function rounds(q: URLSearchParams) {
  const limit = Math.min(num(q.get('limit'), 30), 200);
  let rows = await query<{ round_id: number; first: Date; last: Date }>(
    `SELECT ids.round_id,
			(SELECT MIN(ts) FROM metric_sample s WHERE s.round_id = ids.round_id) AS first,
			(SELECT MAX(ts) FROM metric_sample s WHERE s.round_id = ids.round_id) AS last
		 FROM (SELECT DISTINCT round_id FROM metric_event UNION SELECT DISTINCT round_id FROM metric_round) ids
		 ORDER BY ids.round_id DESC LIMIT ?`,
    [limit],
  );
  // Under a minute of samples (a test world's, or a boot that never got going) has nothing to show.
  rows = rows.filter(
    (r) =>
      r.first &&
      new Date(r.last).getTime() - new Date(r.first).getTime() >= 60_000,
  );
  const ids = rows.map((r) => r.round_id);
  const meta = new Map<number, Record<string, unknown>>();
  for (const e of await roundEvents(ids)) {
    const m = meta.get(e.round_id) ?? {};
    const payload = e.payload ? JSON.parse(e.payload) : {};
    if (e.category === 'start')
      Object.assign(m, {
        map: payload.map,
        commit: payload.commit,
        started: e.ts,
      });
    if (e.category === 'end')
      Object.assign(m, {
        ended: e.ts,
        duration_s: payload.duration_s,
        end_players: payload.players,
      });
    if (e.category === 'shutdown') m.shutdown = e.ts;
    meta.set(e.round_id, m);
  }
  const counts = ids.length
    ? await query<{ round_id: number; kind: string; n: number }>(
        `SELECT round_id, kind, SUM(COALESCE(JSON_VALUE(payload, '$.count'), 1)) AS n FROM metric_event
				 WHERE round_id IN (${placeholders(ids.length)}) AND kind IN ('runtime', 'overrun', 'ticket', 'admin_verb')
				 AND (kind <> 'ticket' OR category = 'opened') GROUP BY round_id, kind`,
        ids,
      )
    : [];
  const headline = [
    'server/tick/avg',
    'server/tick/p95',
    'server/time_dilation/current',
    'players/online',
    'server/overruns',
    'errors/runtimes',
  ];
  const out = [];
  for (const r of rows) {
    const stats = await roundStats(r.round_id);
    const pick = (name: string) => stats.get(name);
    const c = (kind: string) =>
      Number(
        counts.find((x) => x.round_id === r.round_id && x.kind === kind)?.n ??
          0,
      );
    const roundStalls = await stallsFor(r.round_id);
    out.push({
      id: r.round_id,
      first: r.first,
      last: r.last,
      live:
        r.round_id === rows[0]?.round_id &&
        Date.now() - new Date(r.last).getTime() <
          config.staleRoundMinutes * 60_000 &&
        !meta.get(r.round_id)?.ended,
      ...meta.get(r.round_id),
      tick_avg: pick(headline[0])?.mean ?? null,
      tick_p95: pick(headline[1])?.p95 ?? null,
      dilation_avg: pick(headline[2])?.mean ?? null,
      players_peak: pick(headline[3])?.max ?? null,
      overruns: Math.round(
        (pick(headline[4])?.mean ?? 0) * (pick(headline[4])?.n ?? 0),
      ),
      runtimes: Math.round(
        (pick(headline[5])?.mean ?? 0) * (pick(headline[5])?.n ?? 0),
      ),
      runtime_signatures: c('runtime'),
      tickets: c('ticket'),
      admin_verbs: c('admin_verb'),
      stalls: roundStalls.length,
      stalled_s: roundStalls.reduce((a, x) => a + x.seconds, 0),
    });
  }
  return out;
}

/** Time series for metrics in a round: [{name, unit, points: [[epoch ms, value]]}]. */
export async function series(q: URLSearchParams) {
  const roundId = num(q.get('round'), 0);
  const names = (q.get('keys') ?? '').split(',').filter(Boolean).slice(0, 12);
  if (!roundId || !names.length) return [];
  const rows = await query<{
    name: string;
    unit: string;
    ts: Date;
    value: number;
  }>(
    `SELECT k.name, k.unit, s.ts, s.value FROM metric_sample s JOIN metric_key k ON k.id = s.key_id
		 WHERE s.round_id = ? AND k.name IN (${placeholders(names.length)}) ORDER BY s.t`,
    [roundId, ...names],
  );
  const byName = new Map<
    string,
    { name: string; unit: string; points: [number, number][] }
  >();
  for (const name of names) byName.set(name, { name, unit: '', points: [] });
  for (const r of rows) {
    const s = byName.get(r.name);
    if (!s) continue;
    s.unit = r.unit;
    s.points.push([new Date(r.ts).getTime(), r.value]);
  }
  return [...byName.values()].filter((s) => s.points.length);
}

/** One category's metrics in a round, grouped by subcategory, each against its baseline. */
export async function breakdown(q: URLSearchParams) {
  const roundId = num(q.get('round'), 0);
  const category = q.get('category') ?? 'mc';
  const stat = (q.get('stat') ?? 'p95') as keyof Summary;
  const metric = q.get('metric') ?? '';
  const stats = [...(await roundStats(roundId)).values()].filter(
    (s) =>
      s.category === category && (!metric || s.name.endsWith(`/${metric}`)),
  );
  const baselines = await baselineValues(
    roundId,
    stats.map((s) => s.name),
    stat,
  );
  const rows = stats
    .map((s) => flag(s, stat, baselines.get(s.name)))
    .sort((a, b) => b.value - a.value);
  const metrics = [
    ...new Set(
      [...(await roundStats(roundId)).values()]
        .filter((s) => s.category === category)
        .map((s) => s.name.split('/').pop()),
    ),
  ];
  return { round: roundId, category, stat, metric, metrics, rows };
}

/** Every metric of a round flagged as an outlier against its own history, worst first. */
export async function outliers(q: URLSearchParams) {
  const roundId = num(q.get('round'), 0);
  const stat = (q.get('stat') ?? 'p95') as keyof Summary;
  const stats = [...(await roundStats(roundId)).values()];
  const baselines = await baselineValues(
    roundId,
    stats.map((s) => s.name),
    stat,
  );
  return stats
    .map((s) => flag(s, stat, baselines.get(s.name)))
    .filter((f) => f.outlier)
    .sort((a, b) => (b.ratio ?? 99) - (a.ratio ?? 99))
    .slice(0, 40);
}

/** One metric across recent rounds (rollups, plus the live round computed on the fly). */
export async function trend(q: URLSearchParams) {
  const name = q.get('key') ?? '';
  const limit = Math.min(num(q.get('limit'), 40), 200);
  const rows = await query<Summary & { round_id: number }>(
    `SELECT r.round_id, r.n, r.mean, r.min, r.p50, r.p95, r.p99, r.max FROM metric_round r JOIN metric_key k ON k.id = r.key_id
		 WHERE k.name = ? ORDER BY r.round_id DESC LIMIT ?`,
    [name, limit],
  );
  const live = await query<{ round_id: number }>(
    `SELECT DISTINCT s.round_id FROM metric_sample s WHERE s.round_id > ? AND NOT EXISTS (SELECT 1 FROM metric_round r WHERE r.round_id = s.round_id)`,
    [rows[0]?.round_id ?? 0],
  );
  for (const l of live) {
    const s = (await roundStats(l.round_id)).get(name);
    if (s)
      rows.unshift({
        round_id: l.round_id,
        n: s.n,
        mean: s.mean,
        min: s.min,
        p50: s.p50,
        p95: s.p95,
        p99: s.p99,
        max: s.max,
      });
  }
  return rows.reverse();
}

export async function categories(q: URLSearchParams) {
  const roundId = num(q.get('round'), 0);
  const stats = [...(await roundStats(roundId)).values()];
  const out: Record<string, { subcategories: number; metrics: string[] }> = {};
  for (const s of stats) {
    out[s.category] ??= { subcategories: 0, metrics: [] };
    const c = out[s.category];
    const metric = s.name.split('/').pop() ?? '';
    if (!c.metrics.includes(metric)) c.metrics.push(metric);
  }
  for (const [category, entry] of Object.entries(out))
    entry.subcategories = new Set(
      stats.filter((s) => s.category === category).map((s) => s.subcategory),
    ).size;
  return out;
}

// ---------------------------------------------------------------- events

function sourceLink(where: string, commit?: string): string | null {
  const m = /^(.+\.dm)[,:](\d+)$/.exec(where ?? '');
  return m
    ? `${config.repoUrl}/blob/${commit || 'master'}/${m[1].replaceAll('\\', '/')}#L${m[2]}`
    : null;
}

export async function runtimes(q: URLSearchParams) {
  const days = Math.min(num(q.get('days'), 14), 365);
  const roundId = num(q.get('round'), 0);
  const where = roundId ? 'round_id = ?' : 'ts > NOW() - INTERVAL ? DAY';
  const groups = await query<{
    signature: string;
    message: string;
    location: string;
    total: number;
    rounds: number;
    first_seen: Date;
    last_seen: Date;
  }>(
    `SELECT signature, MAX(message) AS message, MAX(JSON_VALUE(payload, '$.where')) AS location,
			SUM(JSON_VALUE(payload, '$.count')) AS total, COUNT(DISTINCT round_id) AS rounds, MIN(ts) AS first_seen, MAX(ts) AS last_seen
		 FROM metric_event WHERE kind = 'runtime' AND ${where} GROUP BY signature ORDER BY total DESC LIMIT 200`,
    [roundId || days],
  );
  const sigs = groups.map((g) => g.signature);
  const firstEver = sigs.length
    ? await query<{ signature: string; first: Date }>(
        `SELECT signature, MIN(ts) AS first FROM metric_event WHERE kind = 'runtime' AND signature IN (${placeholders(sigs.length)}) GROUP BY signature`,
        sigs,
      )
    : [];
  const daily = sigs.length
    ? await query<{ signature: string; d: string; n: number }>(
        `SELECT signature, DATE_FORMAT(ts, '%Y-%m-%d') AS d, SUM(JSON_VALUE(payload, '$.count')) AS n FROM metric_event
				 WHERE kind = 'runtime' AND ts > NOW() - INTERVAL ? DAY AND signature IN (${placeholders(sigs.length)}) GROUP BY signature, d`,
        [days, ...sigs],
      )
    : [];
  const latestCommit = await query<{ payload: string }>(
    `SELECT payload FROM metric_event WHERE kind = 'round' AND category = 'start' ORDER BY id DESC LIMIT 1`,
  );
  const commit = latestCommit[0]
    ? JSON.parse(latestCommit[0].payload ?? '{}').commit
    : undefined;
  const dayList: string[] = [];
  for (let i = days - 1; i >= 0; i--)
    dayList.push(
      new Date(Date.now() - i * 86_400_000).toISOString().slice(0, 10),
    );
  return {
    days: dayList,
    groups: groups.map((g) => {
      const first =
        firstEver.find((f) => f.signature === g.signature)?.first ??
        g.first_seen;
      return {
        ...g,
        total: Number(g.total),
        first_seen: first,
        is_new: Date.now() - new Date(first).getTime() < 86_400_000,
        link: sourceLink(g.location, commit),
        daily: dayList.map((d) =>
          Number(
            daily.find((x) => x.signature === g.signature && x.d === d)?.n ?? 0,
          ),
        ),
      };
    }),
  };
}

export async function overruns(q: URLSearchParams) {
  const roundId = num(q.get('round'), 0);
  const days = Math.min(num(q.get('days'), 14), 365);
  const where = roundId ? 'round_id = ?' : 'ts > NOW() - INTERVAL ? DAY';
  const events = await query<{
    round_id: number;
    ts: Date;
    category: string;
    payload: string;
  }>(
    `SELECT round_id, ts, category, payload FROM metric_event WHERE kind = 'overrun' AND ${where} ORDER BY ts DESC LIMIT 300`,
    [roundId || days],
  );
  const byTop = new Map<
    string,
    { name: string; count: number; worst: number }
  >();
  const list = events.map((e) => {
    const p = JSON.parse(e.payload ?? '{}');
    const top = e.category || 'unknown';
    const entry = byTop.get(top) ?? { name: top, count: 0, worst: 0 };
    entry.count++;
    entry.worst = Math.max(entry.worst, p.usage ?? 0);
    byTop.set(top, entry);
    return {
      round_id: e.round_id,
      ts: e.ts,
      top,
      usage: p.usage,
      maptick: p.maptick,
      streak: p.streak,
      breakdown: p.breakdown ?? [],
      top_systems: p.top_systems ?? [],
    };
  });
  return {
    events: list,
    by_top: [...byTop.values()].sort((a, b) => b.count - a.count),
  };
}

// ---------------------------------------------------------------- staff

export async function staff(q: URLSearchParams) {
  const days = Math.min(num(q.get('days'), 30), 365);
  const tickets = await query<{
    round_id: number;
    category: string;
    signature: string;
    ckey: string;
    message: string;
    ts: Date;
    payload: string;
  }>(
    `SELECT round_id, category, signature, ckey, message, ts, payload FROM metric_event WHERE kind = 'ticket' AND ts > NOW() - INTERVAL ? DAY ORDER BY ts`,
    [days],
  );
  type T = {
    key: string;
    round_id: number;
    id: string;
    ckey: string;
    title: string;
    level: string;
    opened?: Date;
    handled_s?: number;
    handler?: string;
    closed_s?: number;
    outcome?: string;
  };
  const byTicket = new Map<string, T>();
  for (const e of tickets) {
    const key = `${e.round_id}#${e.signature}`;
    const p = JSON.parse(e.payload ?? '{}');
    const t: T = byTicket.get(key) ?? {
      key,
      round_id: e.round_id,
      id: e.signature,
      ckey: e.ckey,
      title: e.message,
      level: p.level,
    };
    if (e.category === 'opened') t.opened = e.ts;
    if (e.category === 'handled' && t.handled_s === undefined)
      Object.assign(t, { handled_s: p.age_s, handler: p.handler });
    if (e.category === 'closed' || e.category === 'resolved')
      Object.assign(t, {
        closed_s: p.age_s,
        outcome: e.category,
        handler: t.handler ?? p.handler,
      });
    byTicket.set(key, t);
  }
  const all = [...byTicket.values()].filter((t) => t.opened);
  const handled = all
    .filter((t) => t.handled_s !== undefined)
    .map((t) => t.handled_s as number);
  const closed = all
    .filter((t) => t.closed_s !== undefined)
    .map((t) => t.closed_s as number);
  const dayList: string[] = [];
  for (let i = days - 1; i >= 0; i--)
    dayList.push(
      new Date(Date.now() - i * 86_400_000).toISOString().slice(0, 10),
    );
  const perDay = dayList.map((d) => ({
    day: d,
    admin: all.filter(
      (t) =>
        t.level === 'admin' &&
        new Date(t.opened as Date).toISOString().slice(0, 10) === d,
    ).length,
    mentor: all.filter(
      (t) =>
        t.level === 'mentor' &&
        new Date(t.opened as Date).toISOString().slice(0, 10) === d,
    ).length,
  }));
  const handlers = new Map<string, number>();
  for (const t of all)
    if (t.handler) handlers.set(t.handler, (handlers.get(t.handler) ?? 0) + 1);
  const verbs = await query<{
    verb: string;
    category: string;
    n: number;
    admins: number;
  }>(
    `SELECT message AS verb, category, COUNT(*) AS n, COUNT(DISTINCT ckey) AS admins FROM metric_event
		 WHERE kind = 'admin_verb' AND ts > NOW() - INTERVAL ? DAY GROUP BY message, category ORDER BY n DESC LIMIT 40`,
    [days],
  );
  const admins = await query<{
    ckey: string;
    n: number;
    rounds: number;
    last: Date;
  }>(
    `SELECT ckey, COUNT(*) AS n, COUNT(DISTINCT round_id) AS rounds, MAX(ts) AS last FROM metric_event
		 WHERE kind = 'admin_verb' AND ts > NOW() - INTERVAL ? DAY GROUP BY ckey ORDER BY n DESC`,
    [days],
  );
  const recent = await query<{
    ts: Date;
    ckey: string;
    message: string;
    category: string;
    round_id: number;
  }>(
    `SELECT ts, ckey, message, category, round_id FROM metric_event WHERE kind = 'admin_verb' ORDER BY id DESC LIMIT 100`,
  );
  const hs = summarize(handled);
  const cs = summarize(closed);
  return {
    days,
    totals: {
      tickets: all.length,
      unhandled: all.filter(
        (t) => t.handled_s === undefined && t.closed_s === undefined,
      ).length,
      handled: handled.length,
    },
    time_to_handle: { median: hs.p50, p90: summarize(handled).p95, n: hs.n },
    time_to_close: { median: cs.p50, p90: cs.p95, n: cs.n },
    per_day: perDay,
    handlers: [...handlers.entries()]
      .map(([ckey, n]) => ({ ckey, n }))
      .sort((a, b) => b.n - a.n),
    recent_tickets: all.slice(-50).reverse(),
    verbs: verbs.map((v) => ({
      ...v,
      n: Number(v.n),
      admins: Number(v.admins),
    })),
    admins: admins.map((a) => ({
      ...a,
      n: Number(a.n),
      rounds: Number(a.rounds),
    })),
    recent_verbs: recent,
  };
}

// ---------------------------------------------------------------- tests and benchmarks

export async function tests(q: URLSearchParams) {
  const days = Math.min(num(q.get('days'), 60), 365);
  const runs = await query(
    `SELECT id, ts, commit_hash, branch, label, host, clean, duration_s, passed, failed, skipped, focused FROM test_run
		 WHERE ts > NOW() - INTERVAL ? DAY ORDER BY ts DESC LIMIT 200`,
    [days],
  );
  // Flaky: the same test both passed and failed on one commit.
  const flaky = await query<{
    test: string;
    commits: number;
    fails: number;
    passes: number;
    last_message: string;
  }>(
    `SELECT x.test, COUNT(*) AS commits, SUM(x.fails) AS fails, SUM(x.passes) AS passes, MAX(x.last_message) AS last_message FROM (
			SELECT r.test, t.commit_hash, SUM(r.status = 1) AS fails, SUM(r.status = 0) AS passes, MAX(IF(r.status = 1, r.message, '')) AS last_message
			FROM test_result r JOIN test_run t ON t.id = r.run_id WHERE t.ts > NOW() - INTERVAL ? DAY GROUP BY r.test, t.commit_hash
			HAVING fails > 0 AND passes > 0
		) x GROUP BY x.test ORDER BY fails DESC LIMIT 50`,
    [days],
  );
  const failing = await query<{
    test: string;
    fails: number;
    runs: number;
    last_message: string;
    last_fail: Date;
  }>(
    `SELECT r.test, SUM(r.status = 1) AS fails, COUNT(*) AS runs, MAX(IF(r.status = 1, r.message, '')) AS last_message, MAX(IF(r.status = 1, t.ts, NULL)) AS last_fail
		 FROM test_result r JOIN test_run t ON t.id = r.run_id WHERE t.ts > NOW() - INTERVAL ? DAY GROUP BY r.test HAVING fails > 0 ORDER BY fails DESC LIMIT 50`,
    [days],
  );
  const slowest = await query<{
    test: string;
    avg_s: number;
    max_s: number;
    runs: number;
  }>(
    `SELECT r.test, AVG(r.duration_s) AS avg_s, MAX(r.duration_s) AS max_s, COUNT(*) AS runs FROM test_result r JOIN test_run t ON t.id = r.run_id
		 WHERE t.ts > NOW() - INTERVAL ? DAY AND r.status <> 2 GROUP BY r.test ORDER BY avg_s DESC LIMIT 25`,
    [days],
  );
  const num2 = <T extends Record<string, unknown>>(rows: T[]) =>
    rows.map((r) =>
      Object.fromEntries(
        Object.entries(r).map(([k, v]) => [
          k,
          typeof v === 'bigint' ? Number(v) : v,
        ]),
      ),
    );
  return {
    runs: num2(runs as Record<string, unknown>[]),
    flaky: num2(flaky),
    failing: num2(failing),
    slowest: num2(slowest),
  };
}

export async function testHistory(q: URLSearchParams) {
  const name = q.get('name') ?? '';
  return query(
    `SELECT t.id AS run_id, t.ts, t.commit_hash, t.label, r.status, r.duration_s, r.message FROM test_result r JOIN test_run t ON t.id = r.run_id
		 WHERE r.test = ? ORDER BY t.ts DESC LIMIT 200`,
    [name],
  );
}

export async function bench(q: URLSearchParams) {
  const runs = await query(
    `SELECT id, ts, commit_hash, branch, label, host, map, iterations FROM bench_run ORDER BY ts DESC LIMIT 100`,
  );
  const metrics = await query<{
    run_id: string;
    name: string;
    category: string;
    value: number;
  }>(
    `SELECT m.run_id, m.name, m.category, m.value, m.unit, m.better FROM bench_metric m JOIN (SELECT id FROM bench_run ORDER BY ts DESC LIMIT 100) r ON r.id = m.run_id`,
  );
  const names = [
    ...new Set(metrics.map((m) => `${m.category}\u0000${m.name}`)),
  ].map((x) => {
    const [category, name] = x.split('\u0000');
    return { category, name };
  });
  const selected = q.get('metric');
  const seriesFor = (name: string) =>
    [...runs]
      .reverse()
      .map((r) => ({
        run: r as { id: string; ts: Date; label: string; commit_hash: string },
        m: metrics.find(
          (m) => m.run_id === (r as { id: string }).id && m.name === name,
        ),
      }))
      .filter((x) => x.m)
      .map((x) => ({
        run_id: x.run.id,
        ts: x.run.ts,
        label: x.run.label,
        commit: x.run.commit_hash,
        value: x.m?.value ?? 0,
      }));
  return { runs, metrics: names, series: selected ? seriesFor(selected) : [] };
}
