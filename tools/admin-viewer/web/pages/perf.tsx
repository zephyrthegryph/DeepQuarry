import { useState } from 'react';
import {
  Badge,
  BarList,
  fmt,
  fmtDuration,
  LineChart,
  type Series,
} from '../charts';
import {
  Card,
  go,
  Loading,
  type PageProps,
  Seg,
  TestRoundsToggle,
  Tile,
  testsParam,
  useApi,
  useIncludeTests,
  when,
} from '../util';

type Round = {
  id: number;
  first: string;
  last: string;
  live: boolean;
  /** A unit-test world's round (only listed with include_tests). */
  test?: boolean;
  map?: string;
  commit?: string;
  started?: string;
  ended?: string;
  duration_s?: number;
  tick_avg: number | null;
  tick_p95: number | null;
  dilation_avg: number | null;
  players_peak: number | null;
  overruns: number;
  runtimes: number;
  runtime_signatures: number;
  tickets: number;
  admin_verbs: number;
  stalls: number;
  stalled_s: number;
};

type Flagged = {
  name: string;
  category: string;
  subcategory: string;
  unit: string;
  value: number;
  baseline: number | null;
  ratio: number | null;
  outlier: boolean;
  baseline_rounds: number;
  mean: number;
  p95: number;
  max: number;
  n: number;
};

/** The round a page shows: ?round=, else the latest (the latest real round unless test rounds are on). */
function useRound(params: URLSearchParams) {
  const tests = useIncludeTests();
  const rounds = useApi<Round[]>(
    `/api/rounds?limit=60${testsParam(tests[0])}`,
    30_000,
  );
  const requested = Number(params.get('round') ?? 0);
  const round =
    rounds.data?.find((r) => r.id === requested) ?? rounds.data?.[0] ?? null;
  return { rounds, round, tests };
}

function RoundPicker({
  rounds,
  round,
  page,
  tests,
  extra = {},
}: {
  rounds: Round[];
  round: Round;
  page: string;
  tests: [boolean, (on: boolean) => void];
  extra?: Record<string, string>;
}) {
  return (
    <>
      <TestRoundsToggle value={tests[0]} onChange={tests[1]} />
      <select
        value={round.id}
        onChange={(e) => go(page, { ...extra, round: e.target.value })}
        aria-label="Round"
      >
        {rounds.map((r) => (
          <option key={r.id} value={r.id}>
            Round {r.id} · {when(r.started ?? r.first)}
            {r.live ? ' · live' : ''}
            {r.test ? ' · test' : ''}
          </option>
        ))}
      </select>
    </>
  );
}

const roundDuration = (r: Round) =>
  r.duration_s ??
  (new Date(r.last).getTime() - new Date(r.started ?? r.first).getTime()) /
    1000;

function OutlierTable({ rows, roundId }: { rows: Flagged[]; roundId: number }) {
  if (!rows.length)
    return (
      <div className="empty">
        No metric is out of line with its last rounds.
      </div>
    );
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Metric</th>
            <th className="num">This round</th>
            <th className="num">Usual</th>
            <th className="num">Change</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr
              key={r.name}
              className="click"
              onClick={() =>
                go('performance', {
                  round: roundId,
                  category: r.category,
                  metric: r.name.split('/').pop(),
                  key: r.name,
                })
              }
            >
              <td className="mono" style={{ wordBreak: 'break-all' }}>
                {r.name}
              </td>
              <td className="num">{fmt(r.value, r.unit)}</td>
              <td className="num">{fmt(r.baseline, r.unit)}</td>
              <td className="num">
                <Badge kind={(r.ratio ?? 99) >= 3 ? 'critical' : 'serious'}>
                  {r.ratio ? `${fmt(r.ratio)}×` : 'new'}
                </Badge>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function useSeries(roundId: number | undefined, keys: string[]) {
  return useApi<{ name: string; unit: string; points: [number, number][] }[]>(
    roundId
      ? `/api/series?round=${roundId}&keys=${encodeURIComponent(keys.join(','))}`
      : null,
    30_000,
  );
}

const asSeries = (
  rows: { name: string; points: [number, number][] }[] | null,
  labels: Record<string, string>,
): Series[] =>
  (rows ?? []).map((r) => ({
    name: labels[r.name] ?? r.name,
    points: r.points,
  }));

export function OverviewPage({ params }: PageProps) {
  const { rounds, round, tests } = useRound(params);
  const tick = useSeries(round?.id, [
    'server/tick/avg',
    'server/tick/p95',
    'server/tick/max',
  ]);
  const dilation = useSeries(round?.id, [
    'server/time_dilation/current',
    'server/time_dilation/avg',
  ]);
  const players = useSeries(round?.id, [
    'players/online',
    'players/living',
    'staff/admins_present',
  ]);
  const errors = useSeries(round?.id, ['errors/runtimes', 'server/overruns']);
  const lanes = useSeries(round?.id, [
    'lane/simulation/ms_per_s',
    'lane/derived/ms_per_s',
    'lane/presentation/ms_per_s',
    'lane/background/ms_per_s',
    'lane/urgent/ms_per_s',
  ]);
  const out = useApi<Flagged[]>(
    round ? `/api/outliers?round=${round.id}` : null,
    60_000,
  );
  const stalls = useApi<{ from: string; to: string; seconds: number }[]>(
    round ? `/api/stalls?round=${round.id}` : null,
    60_000,
  );
  if (!rounds.data) return <Loading error={rounds.error} />;
  if (!round)
    return (
      <div className="empty">
        No rounds recorded yet. Enable METRICS_ENABLED in dbconfig.txt.
      </div>
    );
  return (
    <>
      <div className="page-head">
        <h1>
          Round {round.id}{' '}
          {round.live ? (
            <Badge kind="good">live</Badge>
          ) : (
            <Badge kind="info">finished</Badge>
          )}
        </h1>
        <div className="filters">
          <RoundPicker
            rounds={rounds.data}
            round={round}
            page="overview"
            tests={tests}
          />
        </div>
      </div>
      <div className="tiles">
        <Tile
          label="Average tick usage"
          value={fmt(round.tick_avg, '%')}
          note={`p95 ${fmt(round.tick_p95, '%')}`}
        />
        <Tile
          label="Time dilation (avg)"
          value={fmt(round.dilation_avg, '%')}
        />
        <Tile label="Peak players" value={fmt(round.players_peak)} />
        <Tile label="Tick overruns" value={fmt(round.overruns)} />
        <Tile
          label="Runtimes"
          value={fmt(round.runtimes)}
          note={`${round.runtime_signatures} distinct`}
        />
        <Tile
          label="Length"
          value={fmtDuration(roundDuration(round))}
          note={round.map ?? ''}
        />
        <Tile
          label="Stalls"
          value={
            round.stalls ? <Badge kind="critical">{round.stalls}</Badge> : '0'
          }
          note={
            round.stalls
              ? `${fmtDuration(round.stalled_s)} frozen`
              : 'no sampling gaps'
          }
        />
      </div>
      {stalls.data && stalls.data.length > 0 && (
        <div style={{ marginBottom: 14 }}>
          <Card
            title="Server stalls"
            sub="Periods with no samples: the world stopped running its scheduler (a freeze or a crash). Check the runtime log for what was running."
          >
            <table>
              <thead>
                <tr>
                  <th>From</th>
                  <th>To</th>
                  <th className="num">Frozen for</th>
                </tr>
              </thead>
              <tbody>
                {stalls.data.map((s) => (
                  <tr key={s.from}>
                    <td>{when(s.from)}</td>
                    <td>{when(s.to)}</td>
                    <td className="num">
                      <Badge kind={s.seconds >= 300 ? 'critical' : 'serious'}>
                        {fmtDuration(s.seconds)}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </div>
      )}
      <div className="grid cols-2">
        <Card
          title="Tick usage"
          sub="Percent of each server tick used, per 10 s sample. Above 100% is an overrun."
        >
          {tick.data ? (
            <LineChart
              series={asSeries(tick.data, {
                'server/tick/avg': 'Average',
                'server/tick/p95': 'p95',
                'server/tick/max': 'Worst tick',
              })}
              unit="%"
            />
          ) : (
            <Loading error={tick.error} />
          )}
        </Card>
        <Card
          title="Time dilation"
          sub="How far game time fell behind real time."
        >
          {dilation.data ? (
            <LineChart
              series={asSeries(dilation.data, {
                'server/time_dilation/current': 'Current',
                'server/time_dilation/avg': 'Rolling average',
              })}
              unit="%"
            />
          ) : (
            <Loading error={dilation.error} />
          )}
        </Card>
        <Card
          title="Scheduler lanes"
          sub="Object-model work per lane, in ms per second of real time."
        >
          {lanes.data ? (
            <LineChart
              series={asSeries(lanes.data, {
                'lane/simulation/ms_per_s': 'Simulation',
                'lane/derived/ms_per_s': 'Derived',
                'lane/presentation/ms_per_s': 'Presentation',
                'lane/background/ms_per_s': 'Background',
                'lane/urgent/ms_per_s': 'Urgent',
              })}
              unit="ms/s"
            />
          ) : (
            <Loading error={lanes.error} />
          )}
        </Card>
        <Card
          title="Players and staff"
          sub="Connected clients, living players and admins on duty."
        >
          {players.data ? (
            <LineChart
              series={asSeries(players.data, {
                'players/online': 'Online',
                'players/living': 'Living',
                'staff/admins_present': 'Admins on duty',
              })}
            />
          ) : (
            <Loading error={players.error} />
          )}
        </Card>
        <Card title="Errors" sub="Runtimes and overrun ticks per 10 s sample.">
          {errors.data ? (
            <LineChart
              series={asSeries(errors.data, {
                'errors/runtimes': 'Runtimes',
                'server/overruns': 'Overrun ticks',
              })}
            />
          ) : (
            <Loading error={errors.error} />
          )}
        </Card>
        <Card
          title="Outliers this round"
          sub="Metrics whose p95 is at least 1.5× their median over recent rounds."
        >
          {out.data ? (
            <OutlierTable rows={out.data} roundId={round.id} />
          ) : (
            <Loading error={out.error} />
          )}
        </Card>
      </div>
    </>
  );
}

const CATEGORIES = [
  { id: 'mc', label: 'MC subsystems', metrics: ['cost_ms', 'tick_usage'] },
  { id: 'service', label: 'World services', metrics: ['ms_per_s'] },
  { id: 'lane', label: 'OM lanes', metrics: ['ms_per_s', 'backlog'] },
  { id: 'behaviour', label: 'Behaviours', metrics: ['ms_per_s'] },
];

export function PerformancePage({ params }: PageProps) {
  const { rounds, round, tests } = useRound(params);
  const category = params.get('category') ?? 'mc';
  const cat = CATEGORIES.find((c) => c.id === category) ?? CATEGORIES[0];
  const metric = params.get('metric') ?? cat.metrics[0];
  const [stat, setStat] = useState<'mean' | 'p95' | 'max'>('p95');
  const selected = params.get('key');
  const data = useApi<{ rows: Flagged[] }>(
    round
      ? `/api/breakdown?round=${round.id}&category=${category}&metric=${metric}&stat=${stat}`
      : null,
    60_000,
  );
  const trend = useApi<
    { round_id: number; p50: number; p95: number; max: number; mean: number }[]
  >(selected ? `/api/trend?key=${encodeURIComponent(selected)}` : null);
  const inRound = useSeries(
    selected ? round?.id : undefined,
    selected ? [selected] : [],
  );
  if (!rounds.data) return <Loading error={rounds.error} />;
  if (!round) return <div className="empty">No rounds recorded yet.</div>;
  const nav = (extra: Record<string, string | undefined>) =>
    go('performance', { round: round.id, category, metric, ...extra });
  const rows = data.data?.rows ?? [];
  const unit = rows[0]?.unit ?? '';
  const sel = rows.find((r) => r.name === selected);
  return (
    <>
      <div className="page-head">
        <h1>Performance breakdown</h1>
        <div className="filters">
          <RoundPicker
            rounds={rounds.data}
            round={round}
            page="performance"
            tests={tests}
            extra={{ category, metric }}
          />
          <Seg
            value={category}
            options={CATEGORIES.map((c) => ({ id: c.id, label: c.label }))}
            onChange={(c) =>
              go('performance', { round: round.id, category: c })
            }
          />
          {cat.metrics.length > 1 && (
            <Seg
              value={metric}
              options={cat.metrics.map((m) => ({ id: m, label: m }))}
              onChange={(m) => nav({ metric: m })}
            />
          )}
          <Seg
            value={stat}
            options={[
              { id: 'mean', label: 'Mean' },
              { id: 'p95', label: 'p95' },
              { id: 'max', label: 'Max' },
            ]}
            onChange={setStat}
          />
        </div>
      </div>
      <div className="grid cols-2">
        <Card
          title={`${cat.label}: ${metric} (${stat})`}
          sub={`Round ${round.id}, largest first. Orange bars are outliers against the last rounds; the tick is each one's usual value.`}
        >
          <div className="keyline">
            <span>
              <i style={{ background: 'var(--series-1)' }} /> this round
            </span>
            <span>
              <i style={{ background: 'var(--series-2)' }} /> outlier (≥1.5×
              usual)
            </span>
            <span>
              <i style={{ background: 'var(--baseline)', width: 2 }} /> usual
              (median of last rounds)
            </span>
          </div>
          {data.data ? (
            <BarList
              rows={rows.map((r) => ({
                key: r.name,
                label:
                  r.name.split('/').slice(1, -1).join('/') || r.subcategory,
                value: r.value,
                baseline: r.baseline,
                outlier: r.outlier,
                title: `${r.name}: ${fmt(r.value, r.unit)} (usual ${fmt(r.baseline, r.unit)} over ${r.baseline_rounds} rounds)`,
              }))}
              unit={unit}
              selected={selected ?? undefined}
              onSelect={(key) => nav({ key })}
            />
          ) : (
            <Loading error={data.error} />
          )}
        </Card>
        <Card
          title={
            sel ? sel.name.split('/').slice(1, -1).join('/') : 'Pick a row'
          }
          sub={
            sel ? (
              <span className="mono">{sel.name}</span>
            ) : (
              'Click a bar to see it over this round and across rounds.'
            )
          }
        >
          {sel && (
            <>
              <div
                className="tiles"
                style={{ gridTemplateColumns: 'repeat(4, minmax(0, 1fr))' }}
              >
                <Tile label="Mean" value={fmt(sel.mean, sel.unit)} />
                <Tile label="p95" value={fmt(sel.p95, sel.unit)} />
                <Tile label="Max" value={fmt(sel.max, sel.unit)} />
                <Tile
                  label="Usual"
                  value={fmt(sel.baseline, sel.unit)}
                  note={`${sel.baseline_rounds} rounds`}
                />
              </div>
              <h2 style={{ fontSize: 13 }}>This round</h2>
              {inRound.data ? (
                <LineChart
                  series={asSeries(inRound.data, {})}
                  unit={sel.unit}
                  height={160}
                />
              ) : (
                <Loading error={inRound.error} />
              )}
              <h2 style={{ fontSize: 13, marginTop: 12 }}>Across rounds</h2>
              {trend.data ? (
                <LineChart
                  xLabels={trend.data.map((t) => `R${t.round_id}`)}
                  series={[
                    {
                      name: 'p50',
                      points: trend.data.map((t, i) => [i, t.p50]),
                    },
                    {
                      name: 'p95',
                      points: trend.data.map((t, i) => [i, t.p95]),
                    },
                    {
                      name: 'max',
                      points: trend.data.map((t, i) => [i, t.max]),
                    },
                  ]}
                  unit={sel.unit}
                  height={160}
                  markers={trend.data.length < 20}
                />
              ) : (
                <Loading error={trend.error} />
              )}
            </>
          )}
        </Card>
      </div>
    </>
  );
}

export function RoundsPage(_: PageProps) {
  const [includeTests, setIncludeTests] = useIncludeTests();
  const rounds = useApi<Round[]>(
    `/api/rounds?limit=100${testsParam(includeTests)}`,
    30_000,
  );
  if (!rounds.data) return <Loading error={rounds.error} />;
  const list = [...rounds.data].reverse();
  return (
    <>
      <div className="page-head">
        <h1>Rounds</h1>
        <div className="filters">
          <TestRoundsToggle value={includeTests} onChange={setIncludeTests} />
        </div>
      </div>
      {list.length > 1 && (
        <div className="grid cols-2" style={{ marginBottom: 14 }}>
          <Card
            title="Tick usage per round"
            sub="Average and p95 tick usage, oldest to newest."
          >
            <LineChart
              xLabels={list.map((r) => `R${r.id}`)}
              series={[
                {
                  name: 'Average',
                  points: list.map((r, i) => [i, r.tick_avg ?? 0]),
                },
                {
                  name: 'p95',
                  points: list.map((r, i) => [i, r.tick_p95 ?? 0]),
                },
              ]}
              unit="%"
              markers={list.length < 20}
            />
          </Card>
          <Card
            title="Players and runtimes per round"
            sub="Peak players; runtimes are on the Runtimes page."
          >
            <LineChart
              xLabels={list.map((r) => `R${r.id}`)}
              series={[
                {
                  name: 'Peak players',
                  points: list.map((r, i) => [i, r.players_peak ?? 0]),
                },
              ]}
              markers={list.length < 20}
            />
          </Card>
        </div>
      )}
      <Card title="All rounds" sub="Click a round for its overview.">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Round</th>
                <th>Started</th>
                <th>Length</th>
                <th>Map</th>
                <th className="num">Avg tick</th>
                <th className="num">p95 tick</th>
                <th className="num">Dilation</th>
                <th className="num">Peak players</th>
                <th className="num">Overruns</th>
                <th className="num">Runtimes</th>
                <th className="num">Tickets</th>
                <th className="num">Admin verbs</th>
                <th className="num">Stalls</th>
              </tr>
            </thead>
            <tbody>
              {rounds.data.map((r) => (
                <tr
                  key={r.id}
                  className="click"
                  onClick={() => go('overview', { round: r.id })}
                >
                  <td>
                    {r.id} {r.live && <Badge kind="good">live</Badge>}
                    {r.test && <Badge kind="info">test</Badge>}
                  </td>
                  <td>{when(r.started ?? r.first)}</td>
                  <td>{fmtDuration(roundDuration(r))}</td>
                  <td>{r.map ?? '–'}</td>
                  <td className="num">{fmt(r.tick_avg, '%')}</td>
                  <td className="num">{fmt(r.tick_p95, '%')}</td>
                  <td className="num">{fmt(r.dilation_avg, '%')}</td>
                  <td className="num">{fmt(r.players_peak)}</td>
                  <td className="num">{r.overruns}</td>
                  <td className="num">{r.runtimes}</td>
                  <td className="num">{r.tickets}</td>
                  <td className="num">{r.admin_verbs}</td>
                  <td className="num">
                    {r.stalls ? (
                      <Badge kind="critical">{fmtDuration(r.stalled_s)}</Badge>
                    ) : (
                      0
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  );
}
