import { Fragment, useState } from 'react';
import { Badge, BarList, fmt, fmtDuration, LineChart } from '../charts';
import {
  Card,
  go,
  Loading,
  type PageProps,
  Seg,
  Tile,
  useApi,
  when,
} from '../util';

type TestRun = {
  id: string;
  ts: string;
  commit_hash: string;
  branch: string;
  label: string;
  clean: number;
  duration_s: number;
  passed: number;
  failed: number;
  skipped: number;
  focused: number;
};
type TestsData = {
  runs: TestRun[];
  flaky: {
    test: string;
    commits: number;
    fails: number;
    passes: number;
    last_message: string;
  }[];
  failing: {
    test: string;
    fails: number;
    runs: number;
    last_message: string;
    last_fail: string;
  }[];
  slowest: { test: string; avg_s: number; max_s: number; runs: number }[];
};

const short = (test: string) => test.replace('/datum/unit_test/', '');

export function TestsPage({ params }: PageProps) {
  const data = useApi<TestsData>('/api/tests?days=90', 60_000);
  const selected = params.get('test');
  const history = useApi<
    {
      run_id: string;
      ts: string;
      commit_hash: string;
      status: number;
      duration_s: number;
      message: string;
    }[]
  >(
    selected ? `/api/tests/history?name=${encodeURIComponent(selected)}` : null,
  );
  if (!data.data) return <Loading error={data.error} />;
  const full = data.data.runs.filter((r) => !r.focused);
  const last = full[0];
  const chrono = [...full].reverse();
  return (
    <>
      <div className="page-head">
        <h1>Unit tests</h1>
      </div>
      <div className="tiles">
        <Tile
          label="Last full run"
          value={
            last ? (
              last.failed ? (
                <Badge kind="critical">{last.failed} failed</Badge>
              ) : (
                <Badge kind="good">passed</Badge>
              )
            ) : (
              '–'
            )
          }
          note={last ? `${when(last.ts)} · ${last.commit_hash}` : ''}
        />
        <Tile
          label="Tests passed"
          value={last ? fmt(last.passed) : '–'}
          note={last ? `${last.skipped} skipped` : ''}
        />
        <Tile
          label="Suite time"
          value={last ? fmtDuration(last.duration_s) : '–'}
        />
        <Tile
          label="Flaky tests"
          value={fmt(data.data.flaky.length)}
          note="passed and failed on one commit"
        />
        <Tile
          label="Runs recorded"
          value={fmt(data.data.runs.length)}
          note={`${full.length} full, ${data.data.runs.length - full.length} focused`}
        />
      </div>
      <div className="grid cols-2">
        <Card
          title="Full-suite runs"
          sub="Failures per full run, oldest to newest."
        >
          {chrono.length ? (
            <LineChart
              xLabels={chrono.map(
                (r) =>
                  `${r.commit_hash.slice(0, 7)} ${new Date(r.ts).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}`,
              )}
              series={[
                { name: 'Failed', points: chrono.map((r, i) => [i, r.failed]) },
              ]}
              markers
              height={170}
            />
          ) : (
            <div className="empty">No full runs yet.</div>
          )}
        </Card>
        <Card title="Suite duration" sub="Seconds per full run.">
          {chrono.length ? (
            <LineChart
              xLabels={chrono.map((r) => r.commit_hash.slice(0, 7))}
              series={[
                {
                  name: 'Duration',
                  points: chrono.map((r, i) => [i, r.duration_s]),
                },
              ]}
              unit="s"
              markers
              height={170}
            />
          ) : (
            <div className="empty">No full runs yet.</div>
          )}
        </Card>
        <Card
          title="Flaky tests"
          sub="Both passed and failed on the same commit."
        >
          {!data.data.flaky.length ? (
            <div className="empty">
              No test has both passed and failed on one commit.
            </div>
          ) : (
            <TestTable
              rows={data.data.flaky.map((f) => ({
                test: f.test,
                a: `${f.fails} fail / ${f.passes} pass`,
                b: `${f.commits} commit(s)`,
                msg: f.last_message,
              }))}
              selected={selected}
              heads={['Results', 'Commits']}
            />
          )}
        </Card>
        <Card
          title="Failing tests"
          sub="Tests with at least one failure, most first."
        >
          {!data.data.failing.length ? (
            <div className="empty">No failures recorded.</div>
          ) : (
            <TestTable
              rows={data.data.failing.map((f) => ({
                test: f.test,
                a: `${f.fails} of ${f.runs}`,
                b: when(f.last_fail),
                msg: f.last_message,
              }))}
              selected={selected}
              heads={['Failed', 'Last failure']}
            />
          )}
        </Card>
        <Card title="Slowest tests" sub="Average seconds per run.">
          <BarList
            rows={data.data.slowest.map((s) => ({
              key: s.test,
              label: short(s.test),
              value: s.avg_s,
              title: `max ${fmt(s.max_s, 's')} over ${s.runs} runs`,
            }))}
            unit="s"
            onSelect={(k) => go('tests', { test: k })}
            selected={selected ?? undefined}
            limit={15}
          />
        </Card>
        <Card
          title={selected ? short(selected) : 'Test history'}
          sub={
            selected
              ? 'Every recorded run of this test, newest first.'
              : 'Pick a test from the tables.'
          }
        >
          {selected &&
            (history.data ? (
              <>
                <LineChart
                  xLabels={[...history.data]
                    .reverse()
                    .map((h) => h.commit_hash.slice(0, 7))}
                  series={[
                    {
                      name: 'Duration',
                      points: [...history.data]
                        .reverse()
                        .map((h, i) => [i, h.duration_s]),
                    },
                  ]}
                  unit="s"
                  height={140}
                />
                <div className="table-wrap" style={{ maxHeight: 260 }}>
                  <table>
                    <tbody>
                      {history.data.map((h) => (
                        <tr key={h.run_id}>
                          <td>{when(h.ts)}</td>
                          <td className="mono">{h.commit_hash.slice(0, 7)}</td>
                          <td>
                            {h.status === 0 ? (
                              <Badge kind="good">pass</Badge>
                            ) : h.status === 1 ? (
                              <Badge kind="critical">fail</Badge>
                            ) : (
                              <Badge kind="info">skip</Badge>
                            )}
                          </td>
                          <td className="num">{fmt(h.duration_s, 's')}</td>
                          <td className="muted">{h.message}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </>
            ) : (
              <Loading error={history.error} />
            ))}
        </Card>
      </div>
      <div style={{ marginTop: 14 }}>
        <Card title="Recent runs">
          <div className="table-wrap" style={{ maxHeight: 320 }}>
            <table>
              <thead>
                <tr>
                  <th>When</th>
                  <th>Commit</th>
                  <th>Branch</th>
                  <th>Kind</th>
                  <th className="num">Passed</th>
                  <th className="num">Failed</th>
                  <th className="num">Skipped</th>
                  <th className="num">Time</th>
                </tr>
              </thead>
              <tbody>
                {data.data.runs.map((r) => (
                  <tr key={r.id}>
                    <td>{when(r.ts)}</td>
                    <td className="mono">{r.commit_hash}</td>
                    <td className="muted">{r.branch}</td>
                    <td>{r.focused ? 'focused' : r.label || 'full'}</td>
                    <td className="num">{r.passed}</td>
                    <td className="num">
                      {r.failed ? <Badge kind="critical">{r.failed}</Badge> : 0}
                    </td>
                    <td className="num">{r.skipped}</td>
                    <td className="num">{fmtDuration(r.duration_s)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </div>
    </>
  );
}

function TestTable({
  rows,
  selected,
  heads,
}: {
  rows: { test: string; a: string; b: string; msg: string }[];
  selected: string | null;
  heads: [string, string];
}) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Test</th>
            <th>{heads[0]}</th>
            <th>{heads[1]}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <Fragment key={r.test}>
              <tr
                className={`click${selected === r.test ? ' sel' : ''}`}
                onClick={() => go('tests', { test: r.test })}
                title={r.msg}
              >
                <td className="mono">{short(r.test)}</td>
                <td>{r.a}</td>
                <td>{r.b}</td>
              </tr>
              {selected === r.test && r.msg && (
                <tr className="sel msg-row">
                  <td colSpan={3} className="mono">
                    {r.msg}
                  </td>
                </tr>
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  );
}

type BenchData = {
  runs: {
    id: string;
    ts: string;
    commit_hash: string;
    branch: string;
    label: string;
    host: string;
    map: string;
    iterations: number;
  }[];
  metrics: { category: string; name: string }[];
  series: {
    run_id: string;
    ts: string;
    label: string;
    commit: string;
    value: number;
  }[];
};

export function BenchPage({ params }: PageProps) {
  const metric = params.get('metric') ?? 'process/peak_private_mb';
  const data = useApi<BenchData>(
    `/api/bench?metric=${encodeURIComponent(metric)}`,
  );
  const [group, setGroup] = useState<string>(metric.split('/')[0]);
  if (!data.data) return <Loading error={data.error} />;
  const groups = [...new Set(data.data.metrics.map((m) => m.category))];
  const inGroup = data.data.metrics.filter((m) => m.category === group);
  const s = data.data.series;
  return (
    <>
      <div className="page-head">
        <h1>Benchmarks</h1>
        <div className="filters">
          <Seg
            value={group}
            options={groups.map((g) => ({ id: g, label: g }))}
            onChange={setGroup}
          />
          <select
            value={metric}
            onChange={(e) => go('bench', { metric: e.target.value })}
            aria-label="Metric"
          >
            {!inGroup.some((m) => m.name === metric) && (
              <option value={metric}>{metric}</option>
            )}
            {inGroup.map((m) => (
              <option key={m.name} value={m.name}>
                {m.name.split('/').slice(1).join('/')}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div className="tiles">
        <Tile label="Benchmark runs" value={fmt(data.data.runs.length)} />
        <Tile
          label="Latest"
          value={s.length ? fmt(s[s.length - 1].value) : '–'}
          note={metric}
        />
        <Tile
          label="Change vs previous run"
          value={
            s.length > 1
              ? `${fmt(((s[s.length - 1].value - s[s.length - 2].value) / (s[s.length - 2].value || 1)) * 100)}%`
              : '–'
          }
        />
      </div>
      <div className="grid cols-2">
        <Card
          title={metric}
          sub="Median over each run's measured iterations, oldest to newest."
        >
          {s.length ? (
            <LineChart
              xLabels={s.map((x) => `${x.label || x.commit}`)}
              series={[{ name: metric, points: s.map((x, i) => [i, x.value]) }]}
              markers
              height={220}
            />
          ) : (
            <div className="empty">No run measured this metric.</div>
          )}
        </Card>
        <Card title="Runs">
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>When</th>
                  <th>Label</th>
                  <th>Commit</th>
                  <th>Map</th>
                  <th className="num">Iterations</th>
                  <th className="num">{metric.split('/').pop()}</th>
                </tr>
              </thead>
              <tbody>
                {data.data.runs.map((r) => (
                  <tr key={r.id}>
                    <td>{when(r.ts)}</td>
                    <td>{r.label}</td>
                    <td className="mono">{r.commit_hash}</td>
                    <td>{r.map}</td>
                    <td className="num">{r.iterations}</td>
                    <td className="num">
                      {fmt(s.find((x) => x.run_id === r.id)?.value)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </div>
    </>
  );
}
