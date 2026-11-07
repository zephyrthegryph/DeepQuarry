import { useState } from 'react';
import { Tabs } from 'tgui/dq';

function num(value: any, digits = 1): string {
  const number = Number(value);
  return Number.isFinite(number) ? number.toFixed(digits) : '0.0';
}

function severity(value: number): string {
  if (value > 100) return 'critical';
  if (value > 75) return 'warning';
  return 'healthy';
}

/** Time dilation: a few percent is normal jitter, double digits players feel. */
function tidiSeverity(value: number): string {
  if (value > 25) return 'critical';
  if (value > 10) return 'warning';
  return 'healthy';
}

function Card(props: {
  label: string;
  value: string;
  detail: string;
  level?: string;
}) {
  return (
    <div
      className={`mc-metric-card${props.level && props.level !== 'healthy' ? ` mc-metric-card--${props.level}` : ''}`}
    >
      <div className="mc-metric-label">{props.label}</div>
      <div className="mc-metric-value">{props.value}</div>
      <div className="mc-metric-detail">{props.detail}</div>
    </div>
  );
}

const VIEWS = [
  ['overview', 'Overview'],
  ['ticks', 'Ticks'],
  ['subsystems', 'Subsystems'],
  ['kernel', 'Kernel'],
  ['outliers', 'Outliers'],
  ['runtime', 'Runtime'],
];

function varsHref(token: string | null, ref: any) {
  return `byond://?_src_=vars;admin_token=${token};Vars=${ref}`;
}

function Table(props: { headers: string[]; rows: (string | number)[][] }) {
  return (
    <table className="mc-performance-table">
      <thead>
        <tr>
          {props.headers.map((header) => (
            <th key={header}>{header}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {props.rows.map((row) => (
          <tr key={row[0]}>
            {row.map((value, index) => (
              <td key={index}>{value}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Headline({ metrics }: { metrics: any }) {
  const current = Number(metrics.current_usage) || 0;
  const w30 = metrics.window_30s || {};
  return (
    <div className="mc-card-grid">
      <Card
        label="Current tick"
        value={`${num(current)}%`}
        detail={`${num((current * metrics.tick_budget_ms) / 100, 2)} ms of ${num(metrics.tick_budget_ms)} ms`}
        level={severity(current)}
      />
      <Card
        label="TPS"
        value={num(w30.tps)}
        detail={`${num(metrics.target_tps, 0)} target`}
        level={
          Number(w30.tps) < Number(metrics.target_tps) * 0.95
            ? 'warning'
            : 'healthy'
        }
      />
      <Card
        label="30s p99"
        value={`${num(w30.p99)}%`}
        detail={`max ${num(w30.max)}%`}
        level={severity(Number(w30.p99))}
      />
      <Card
        label="Overruns"
        value={`${w30.overruns || 0}`}
        detail={`${w30.samples || 0} ticks / 30s`}
        level={w30.overruns ? 'critical' : 'healthy'}
      />
      <Card
        label="Map send"
        value={`${num(metrics.maptick)}%`}
        detail="BYOND internal map work"
        level={severity(Number(metrics.maptick))}
      />
      <Card
        label="TiDi"
        value={`${num(metrics.tidi)}%`}
        detail={`avg ${num(metrics.tidi_fast)} / ${num(metrics.tidi_medium)} / ${num(metrics.tidi_slow)}`}
        level={tidiSeverity(Number(metrics.tidi))}
      />
    </div>
  );
}

function TickGraph({ metrics }: { metrics: any }) {
  return (
    <section className="mc-panel">
      <h3>Recent tick budget</h3>
      <span className="mc-panel-hint">
        green &lt;75% · amber 75–100% · red overrun
      </span>
      <div className="mc-tick-graph">
        {(metrics.graph || []).map((raw: any, index: number) => {
          const value = Number(raw) || 0;
          return (
            <div
              key={index}
              className={`mc-tick-bar ${severity(value)}`}
              style={{ height: `${Math.max(1, Math.min(value, 200) / 2)}%` }}
              title={`${num(value)}% (${num((value * metrics.tick_budget_ms) / 100, 2)} ms)`}
            />
          );
        })}
        <div className="mc-budget-line" />
      </div>
    </section>
  );
}

function Ticks({ metrics }: { metrics: any }) {
  const windows: [string, any][] = [
    ['5 sec', metrics.window_5s],
    ['30 sec', metrics.window_30s],
    ['5 min', metrics.window_5m],
  ];
  return (
    <>
      <TickGraph metrics={metrics} />
      <section className="mc-panel">
        <h3>Tick distribution</h3>
        <Table
          headers={[
            'Window',
            'TPS',
            'Average',
            'p50',
            'p95',
            'p99',
            'Maximum',
            'Overruns',
            'pctl n',
          ]}
          rows={windows.map(([label, w = {}]) => [
            label,
            num(w.tps),
            `${num(w.avg)}%`,
            `${num(w.p50)}%`,
            `${num(w.p95)}%`,
            `${num(w.p99)}%`,
            `${num(w.max)}%`,
            `${w.overruns || 0}`,
            `${w.percentile_samples || w.samples || 0}`,
          ])}
        />
      </section>
    </>
  );
}

function Runtime({ runtime = {} }: { runtime: any }) {
  const values = [
    ['BYOND CPU', `${num(runtime.cpu)}%`],
    ['Instances', Number(runtime.instances || 0).toLocaleString()],
    ['Clients', `${runtime.clients || 0}`],
    ['Tick drift', num(runtime.tick_drift, 2)],
    ['Sleep factor', num(runtime.sleep_delta, 2)],
    [
      'Queue pressure',
      `${num(runtime.queue_priority, 2)} + ${num(runtime.queue_priority_background, 2)} bg`,
    ],
    [
      'Rust memory',
      `${num(Number(runtime.rust_current_bytes) / 1048576)} / ${num(Number(runtime.rust_peak_bytes) / 1048576)} MiB`,
    ],
  ];
  return (
    <section className="mc-panel">
      <h3>Runtime health</h3>
      <div className="mc-runtime-grid">
        {values.map(([label, value]) => (
          <div className="mc-runtime-item" key={label}>
            <span>{label}</span>
            <strong>{value}</strong>
          </div>
        ))}
      </div>
    </section>
  );
}

function Subsystems(props: { metrics: any; token: string | null }) {
  const rows = (props.metrics.subsystems || [])
    .slice()
    .sort(
      (a: any, b: any) =>
        Number(b.usage) +
        Number(b.overrun) -
        Number(a.usage) -
        Number(a.overrun),
    )
    .filter((s: any) => Number(s.usage) >= 0.05 || Number(s.overrun) >= 0.05);
  return (
    <section className="mc-panel">
      <h3>Subsystem pressure</h3>
      {rows.map((s: any) => {
        const usage = Number(s.usage) || 0;
        const overrun = Number(s.overrun) || 0;
        return (
          <div className="mc-subsystem-row" key={s.ref}>
            <a
              className="mc-subsystem-name"
              href={varsHref(props.token, s.ref)}
            >
              [{s.state || '-'}] {s.name}
            </a>
            <div className="mc-subsystem-track">
              <div
                className={`mc-subsystem-used ${severity(usage)}`}
                style={{ width: `${Math.min(usage, 100)}%` }}
              />
              {overrun > 0 && (
                <div
                  className="mc-subsystem-overrun"
                  style={{ width: `${Math.min(overrun, 100)}%` }}
                />
              )}
            </div>
            <span className="mc-subsystem-value">
              {num(s.cost, 2)} ms · {num(usage)}% · +{num(overrun)}%
            </span>
          </div>
        );
      })}
    </section>
  );
}

function Outliers({ metrics }: { metrics: any }) {
  const [selected, setSelected] = useState<string | null>(null);
  const outliers = (metrics.outliers || []).slice().reverse();
  return (
    <section className="mc-panel">
      <h3>Recent overruns ({outliers.length}/20 retained)</h3>
      {!outliers.length && (
        <div className="mc-empty">No tick overruns recorded.</div>
      )}
      {outliers.map((o: any) => {
        const id = `${o.world_time}-${o.usage}`;
        const open = selected === id;
        return (
          <div className="mc-outlier" key={id}>
            <button
              type="button"
              className="mc-outlier-heading"
              onClick={() => setSelected(open ? null : id)}
            >
              {open ? '▾' : '▸'} t={num(o.world_time / 10)}s · {num(o.usage)}%
              (+{num(o.overrun)}%) · top: {o.top_subsystem} {num(o.top_usage)}%
            </button>
            {open && (
              <div className="mc-outlier-breakdown">
                {(o.breakdown || [])
                  .slice()
                  .sort((a: any, b: any) => Number(b.usage) - Number(a.usage))
                  .map((entry: any) => (
                    <div className="mc-breakdown-row" key={entry.name}>
                      <span>{entry.name}</span>
                      <div className="mc-breakdown-track">
                        <div
                          className={`mc-breakdown-bar ${severity(Number(entry.usage))}`}
                          style={{
                            width: `${Math.min(Number(entry.usage) || 0, 100)}%`,
                          }}
                        />
                      </div>
                      <strong>{num(entry.usage)}%</strong>
                    </div>
                  ))}
                <div className="mc-outlier-note">
                  BYOND map-send usage at capture: {num(o.maptick)}%
                </div>
              </div>
            )}
          </div>
        );
      })}
    </section>
  );
}

function Kernel({ kernel }: { kernel: any }) {
  if (!kernel) {
    return (
      <section className="mc-panel">
        <h3>Kernel: cost by system</h3>
        <div className="mc-empty">No kernel data yet.</div>
      </section>
    );
  }
  const input = kernel.input || {};
  return (
    <section className="mc-panel">
      <h3>Kernel: cost by system</h3>
      <span className="mc-panel-hint">
        {kernel.ticks || 0} ticks over {num(kernel.elapsed_s, 0)} s ·{' '}
        {kernel.overruns || 0} overruns · streak {kernel.streak || 0} (max{' '}
        {kernel.max_streak || 0}) · BYOND reserve {num(kernel.byond_reserve)}% ·
        p50/p95/p99 are ms per tick over the ticks the system ran
      </span>
      <div className="mc-outlier-note">
        Input: wait p50 {num(input.wait_p50_ms, 2)} / p95{' '}
        {num(input.wait_p95_ms, 2)} / p99 {num(input.wait_p99_ms, 2)} ms (
        {num(input.wait_p99_ticks, 2)} ticks) · ran at tick depth p50{' '}
        {input.depth_p50 || 0}% / p95 {input.depth_p95 || 0}% ·{' '}
        {input.clicks || 0} clicks, {input.verbs_queued || 0} verbs queued,{' '}
        {input.verbs_direct || 0} ran at once · queue high water{' '}
        {input.queue_hwm || 0} (now {input.queue_now || 0})
      </div>
      <Table
        headers={[
          'System',
          'Kind',
          'ms/s',
          'p50',
          'p95',
          'p99',
          'Late (ds)',
          'Breaches',
          'Deferred',
          'Overrun share',
        ]}
        rows={(kernel.systems || []).map((s: any) => [
          s.key,
          `${s.kind}${s.lane && s.lane !== s.kind ? ` (${s.lane})` : ''}`,
          num(s.ms_per_s, 2),
          num(s.p50_ms, 2),
          num(s.p95_ms, 2),
          num(s.p99_ms, 2),
          `${s.late_max_ds || 0}`,
          `${s.breaches || 0}`,
          `${s.deferrals || 0}`,
          `${num(Number(s.overrun_share) * 100)}%`,
        ])}
      />
      {kernel.last_overrun && (
        <div className="mc-outlier-note">
          Last overrun: {kernel.last_overrun}
        </div>
      )}
    </section>
  );
}

export function McTab(props: {
  parts: (string | number)[][];
  metrics: any;
  token: string | null;
}) {
  const { metrics, parts, token } = props;
  const [view, setView] = useState('overview');
  return (
    <>
      {metrics && (
        <div className="mc-dashboard">
          <Tabs
            size="small"
            className="mc-navigation"
            tabs={VIEWS.map(([id, label]) => ({
              id,
              label,
              selected: view === id,
            }))}
            onSelect={setView}
          />
          {view === 'overview' && (
            <>
              <Headline metrics={metrics} />
              <TickGraph metrics={metrics} />
            </>
          )}
          {view === 'ticks' && <Ticks metrics={metrics} />}
          {view === 'subsystems' && (
            <Subsystems metrics={metrics} token={token} />
          )}
          {view === 'kernel' && <Kernel kernel={metrics.kernel} />}
          {view === 'outliers' && <Outliers metrics={metrics} />}
          {view === 'runtime' && <Runtime runtime={metrics.runtime} />}
        </div>
      )}
      <details className="mc-details">
        <summary>Detailed controller state</summary>
        <table className="stat-table">
          <tbody>
            {parts.map((part) => (
              <tr key={`${part[0]}`}>
                <td>{part[0]}</td>
                <td>
                  {part[2] ? (
                    <a href={varsHref(token, part[2])}>{part[1]}</a>
                  ) : (
                    part[1]
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </>
  );
}
