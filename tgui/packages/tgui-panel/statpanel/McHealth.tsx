/**
 * The MC Health panel: the Health page of the stat panel's Server view. One scrolling page, top to bottom: health at a glance, recent
 * ticks, what uses the tick, overruns, memory, entities, native (Rust) and a closed Advanced section. The server sends its data
 * (code/content/client/mc_health.dm) only while this page is open, at most once a second. Sections remember open/closed per admin.
 */

import { type ReactNode, useState } from 'react';
import {
  bytes,
  count,
  framePhases,
  histogramPercentile,
  type McHealthData,
  nativeMemoryByArea,
  nativeWork,
  overrunSummary,
  perMinute,
  type RecentTick,
  systemsByCost,
  verdictOf,
} from './mcHealthData';

const OPEN_KEY = 'mc-health-open';

function readOpen(): Record<string, boolean> {
  try {
    return JSON.parse(localStorage.getItem(OPEN_KEY) || '{}');
  } catch {
    return {};
  }
}

function Card(props: {
  id: string;
  title: string;
  summary?: ReactNode;
  closed?: boolean;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(() => readOpen()[props.id] ?? !props.closed);
  const toggle = () => {
    setOpen(!open);
    try {
      localStorage.setItem(
        OPEN_KEY,
        JSON.stringify({ ...readOpen(), [props.id]: !open }),
      );
    } catch {
      // A blocked store only forgets the choice.
    }
  };
  return (
    <section className={`mch-card${open ? '' : ' mch-card--closed'}`}>
      <button type="button" className="mch-card__head" onClick={toggle}>
        <span className="mch-chev">{open ? '▾' : '▸'}</span>
        <h3>{props.title}</h3>
        {props.summary && <span className="mch-sum">{props.summary}</span>}
      </button>
      {open && <div className="mch-card__body">{props.children}</div>}
    </section>
  );
}

const pct = (n: number | undefined, digits = 0) =>
  `${Number(n || 0).toFixed(digits)}%`;

function Health({ data }: { data: McHealthData }) {
  const verdict = verdictOf(data);
  const w = data.window_5s;
  const use = Math.min(100, Math.max(0, w.avg));
  const memory = data.rust?.['process.working_set_bytes'];
  return (
    <div className="mch-health">
      <div className="mch-verdict">
        <span className={`mch-pill mch-pill--${verdict.level}`}>
          {verdict.label}
        </span>
        <span className="mch-why">{verdict.why}</span>
      </div>
      <div
        className="mch-gauge"
        title="Average tick use over the last 5 seconds"
      >
        <div
          className={`mch-gauge__fill mch-gauge__fill--${verdict.level}`}
          style={{ width: `${use}%` }}
        />
        <span>{pct(w.avg)} of each tick</span>
      </div>
      <div className="mch-kpis">
        <Kpi
          label="Speed"
          value={`${w.tps.toFixed(1)}/${data.target_tps} tps`}
        />
        <Kpi label="Slowdown" value={pct(data.tidi, 1)} />
        <Kpi label="Worst 1%" value={pct(w.p99)} />
        <Kpi label="Overruns 5m" value={count(data.window_5m.overruns)} />
        <Kpi label="Players" value={count(data.entities.players)} />
        <Kpi label="Memory" value={memory ? bytes(memory) : '-'} />
      </div>
    </div>
  );
}

const Kpi = (props: { label: string; value: string }) => (
  <div className="mch-kpi">
    <span>{props.label}</span>
    <b>{props.value}</b>
  </div>
);

function Ticks({ data }: { data: McHealthData }) {
  const [win, setWin] = useState<'5s' | '30s' | '5m'>('5s');
  const [pinned, setPinned] = useState<number | null>(null);
  const [hover, setHover] = useState<number | null>(null);
  const ticks = data.ticks || [];
  const top = Math.max(120, ...ticks.map((t) => t[0]));
  const shown = hover ?? pinned;
  const tick: RecentTick | undefined =
    shown === null ? undefined : ticks[shown];
  const w = {
    '5s': data.window_5s,
    '30s': data.window_30s,
    '5m': data.window_5m,
  }[win];
  return (
    <Card
      id="ticks"
      title="Recent ticks"
      summary={`last ${ticks.length} ticks`}
    >
      <div className="mch-winsel">
        {(['5s', '30s', '5m'] as const).map((k) => (
          <button
            key={k}
            type="button"
            className={k === win ? 'mch-on' : undefined}
            onClick={() => setWin(k)}
          >
            {k === '5m' ? '5 min' : k.replace('s', ' s')}
          </button>
        ))}
      </div>
      <div className="mch-timeline" onMouseLeave={() => setHover(null)}>
        <div
          className="mch-budget"
          style={{ bottom: `${(100 / top) * 100}%` }}
          title={`budget ${data.tick_budget_ms} ms`}
        />
        {ticks.map((t, i) => (
          <div
            // biome-ignore lint/suspicious/noArrayIndexKey: ticks are positions in a ring
            key={i}
            className={`mch-bar${t[0] > 100 ? ' mch-bar--over' : ''}${i === pinned ? ' mch-bar--pinned' : ''}`}
            style={{ height: `${(t[0] / top) * 100}%` }}
            onMouseEnter={() => setHover(i)}
            onClick={() => setPinned(i === pinned ? null : i)}
          />
        ))}
      </div>
      <div className="mch-tickdetail">
        {tick ? (
          <>
            <b>{pct(tick[0], 1)}</b>
            {tick[1].map((key, k) => (
              <span key={key}>
                {' '}
                · {key} {tick[2][k]?.toFixed(1)} ms
              </span>
            ))}
          </>
        ) : (
          <span className="mch-muted">
            Hover a tick to see what it was spent on; click to pin it.
          </span>
        )}
      </div>
      <div className="mch-dist">
        <Kpi label="Average" value={pct(w.avg)} />
        <Kpi label="Typical" value={pct(w.p50)} />
        <Kpi label="Slow 5%" value={pct(w.p95)} />
        <Kpi label="Slow 1%" value={pct(w.p99)} />
        <Kpi label="Worst" value={pct(w.max)} />
      </div>
    </Card>
  );
}

function Uses({ data }: { data: McHealthData }) {
  const [all, setAll] = useState(false);
  const systems = systemsByCost(data.kernel?.systems);
  const total = systems.reduce((sum, s) => sum + s.ms_per_s, 0);
  const rows = all ? systems : systems.slice(0, 8);
  return (
    <Card
      id="where"
      title="What uses the tick"
      summary={`${total.toFixed(0)} ms of each second`}
    >
      <div className="mch-stack">
        {systems.slice(0, 8).map((s) => (
          <div
            key={s.key}
            style={{ width: `${s.share * 100}%` }}
            title={`${s.key}: ${s.ms_per_s.toFixed(1)} ms/s`}
          />
        ))}
      </div>
      <table className="mch-table">
        <thead>
          <tr>
            <th>System</th>
            <th>ms/s</th>
            <th>slow 5%</th>
            <th>in overruns</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((s) => (
            <tr key={s.key} title={s.kind ? `${s.key} (${s.kind})` : s.key}>
              <td>{s.key}</td>
              <td>{s.ms_per_s.toFixed(2)}</td>
              <td>{s.p95_ms.toFixed(2)} ms</td>
              <td>{pct(Number(s.overrun_share) * 100)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {systems.length > 8 && (
        <button type="button" className="mch-link" onClick={() => setAll(!all)}>
          {all ? 'Show the top 8' : `Show all ${systems.length}`}
        </button>
      )}
    </Card>
  );
}

function Overruns({ data }: { data: McHealthData }) {
  const [open, setOpen] = useState<number | null>(null);
  const outliers = (data.outliers || [])
    .slice()
    .reverse()
    .filter((o) => o.usage > 100);
  return (
    <Card
      id="ovr"
      title="Overruns"
      summary={`${data.window_5m.overruns} in 5 min`}
    >
      <div className="mch-line">{overrunSummary(outliers, data.window_5m)}</div>
      {outliers.map((o, i) => (
        <div
          key={i}
          className="mch-overrun"
          onClick={() => setOpen(open === i ? null : i)}
        >
          <span>{(o.world_time / 10).toFixed(0)} s</span>{' '}
          <b>+{o.overrun.toFixed(0)}%</b>{' '}
          {(o.top_systems || [])
            .slice(0, 3)
            .map((s) => `${s.key} ${s.ms.toFixed(1)} ms`)
            .join(' · ')}
          {open === i && (
            <div className="mch-muted">
              {o.cause && <div>{o.cause}</div>}
              <div>Map send {pct(o.maptick, 1)}</div>
              {(o.breakdown || []).map(([name, usage]) => (
                <div key={name}>
                  {name}: {pct(usage, 1)}
                </div>
              ))}
            </div>
          )}
        </div>
      ))}
    </Card>
  );
}

function Memory({ data }: { data: McHealthData }) {
  const rust = data.rust || {};
  const total = rust['process.working_set_bytes'];
  const native = rust['alloc.heap.current_bytes'];
  const gc = data.gc;
  return (
    <Card id="mem" title="Memory" summary={total ? bytes(total) : undefined}>
      <div className="mch-kpis">
        <Kpi label="Server process" value={bytes(total)} />
        <Kpi
          label="Peak"
          value={bytes(rust['process.peak_working_set_bytes'])}
        />
        <Kpi label="Native (Rust)" value={bytes(native)} />
        <Kpi
          label="BYOND (the rest)"
          value={total && native ? bytes(total - native) : '-'}
        />
      </div>
      {gc && (
        <>
          <div className="mch-subhead">Clean-up (garbage collector)</div>
          <div className="mch-line">
            {count(gc.queued.reduce((a, b) => a + b, 0))} waiting to be deleted
            · {count(gc.deleted_cleanly)} deleted cleanly · {count(gc.forced)}{' '}
            forced deletes · {count(gc.leaks)} leaks
          </div>
        </>
      )}
    </Card>
  );
}

function Entities({ data }: { data: McHealthData }) {
  const e = data.entities;
  const c = e.census;
  const p = e.previous;
  const grow = (key: 'objects' | 'turfs' | 'areas') => {
    if (!c) return null;
    const rate = perMinute(c[key], p?.[key], c.at, p?.at);
    return rate ? `${rate > 0 ? '+' : ''}${rate.toFixed(0)}/min` : null;
  };
  const cells: [string, number | undefined, string | null][] = [
    ['Players', e.players, null],
    ['Mobs', e.mobs, null],
    ['Living', e.living, null],
    ['Humans', e.humans, null],
    ['Machines', e.machines, null],
    ['Objects', c?.objects, grow('objects')],
    ['Turfs', c?.turfs, grow('turfs')],
    ['Areas', c?.areas, grow('areas')],
  ];
  const churn = Object.entries(data.churn || {}).flatMap(([kind, rows]) =>
    rows.map(([key, n]) => [kind, key, n] as const),
  );
  churn.sort((a, b) => b[2] - a[2]);
  return (
    <Card
      id="ent"
      title="Entities"
      summary={`${count(e.mobs)} mobs · ${count(c?.objects)} objects`}
    >
      <div className="mch-kpis">
        {cells.map(([label, value, change]) => (
          <div key={label} className="mch-kpi">
            <span>{label}</span>
            <b>{count(value)}</b>
            {change && <small>{change}</small>}
          </div>
        ))}
      </div>
      <div className="mch-subhead">Busiest churn, this window</div>
      <table className="mch-table">
        <tbody>
          {churn.slice(0, 10).map(([kind, key, n]) => (
            <tr key={`${kind}${key}`}>
              <td>{kind.replace('_', ' ')}</td>
              <td>{key}</td>
              <td>{count(n)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function Native({ data }: { data: McHealthData }) {
  const rust = data.rust;
  if (!rust) {
    return (
      <Card id="rust" title="Native (Rust)">
        <div className="mch-muted">The native library did not answer.</div>
      </Card>
    );
  }
  const frames = rust['frame.total_us'];
  const avg = frames?.count ? frames.sum / frames.count : null;
  const slow1 = histogramPercentile(frames, 0.99);
  const onCpu = Number(rust['frame.slow_us.on_cpu']) || 0;
  const offCpu = Number(rust['frame.slow_us.off_cpu']) || 0;
  const phases = framePhases(rust);
  const memory = nativeMemoryByArea(rust);
  const work = nativeWork(rust);
  const us = (n: number | null | undefined) =>
    n === null || n === undefined
      ? '-'
      : n >= 1000
        ? `${(n / 1000).toFixed(1)} ms`
        : `${Math.round(n)} µs`;
  return (
    <Card id="rust" title="Native (Rust)" summary={`frame ${us(avg)} avg`}>
      <div className="mch-kpis">
        <Kpi label="Frame avg" value={us(avg)} />
        <Kpi label="Slow 1%" value={us(slow1)} />
        <Kpi
          label="Longest"
          value={us(frames?.max ?? rust['sim.max_frame_us'])}
        />
        <Kpi
          label="Frames"
          value={count(rust['sim.frames_completed'] ?? rust['frame.count'])}
        />
        <Kpi label="Light frames" value={count(rust['sim.light_frames'])} />
        <Kpi label="Skipped" value={count(rust['sim.dispatches_skipped'])} />
        <Kpi label="Calls into Rust" value={count(rust['ffi.calls_total'])} />
        <Kpi label="Errors" value={count(rust['ffi.errors_total'])} />
        <Kpi label="Background jobs" value={count(rust['jobs.pending'])} />
      </div>
      {onCpu + offCpu > 0 && (
        <div className="mch-line">
          Slow frames: {Math.round((offCpu / (onCpu + offCpu)) * 100)}% of their
          time off the CPU (waiting, not working).
        </div>
      )}
      {phases.length > 0 && (
        <>
          <div className="mch-subhead">Where a frame goes (avg per frame)</div>
          <table className="mch-table">
            <tbody>
              {phases.slice(0, 8).map(([label, value]) => (
                <tr key={label}>
                  <td>{label}</td>
                  <td>{us(value)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
      {work.length > 0 && (
        <>
          <div className="mch-subhead">Work the native world is doing</div>
          <table className="mch-table">
            <thead>
              <tr>
                <th>Field / law</th>
                <th>awake</th>
                <th>stepped</th>
              </tr>
            </thead>
            <tbody>
              {work.slice(0, 10).map(([name, awake, stepped]) => (
                <tr key={name}>
                  <td>{name.replace(/_/g, ' ')}</td>
                  <td>{count(awake)}</td>
                  <td>{count(stepped)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
      {memory.length > 0 && (
        <>
          <div className="mch-subhead">Native memory by area</div>
          <div className="mch-line">
            {memory.map(([area, n]) => `${area} ${bytes(n)}`).join(' · ')}
          </div>
        </>
      )}
    </Card>
  );
}

function Advanced(props: {
  data: McHealthData;
  location?: string;
}) {
  const { data } = props;
  const input = data.kernel?.input || {};
  return (
    <Card
      id="adv"
      title="Advanced"
      summary="raw controller state, tools"
      closed
    >
      <div className="mch-links">
        <a href="byond://winset?command=Tick-Report">Tick Report</a>
      </div>
      <table className="mch-table">
        <tbody>
          {props.location && (
            <tr>
              <td>Location</td>
              <td>{props.location}</td>
            </tr>
          )}
          <tr>
            <td>BYOND CPU</td>
            <td>{pct(data.runtime?.cpu)}</td>
          </tr>
          <tr>
            <td>Tick drift</td>
            <td>{count(data.runtime?.tick_drift)} ticks</td>
          </tr>
          <tr>
            <td>Map send (BYOND)</td>
            <td>
              {pct(data.maptick, 1)} now, reserve{' '}
              {pct(data.kernel?.byond_reserve, 1)}
            </td>
          </tr>
          <tr>
            <td>Input wait p99</td>
            <td>{Number(input.wait_p99_ms || 0).toFixed(2)} ms</td>
          </tr>
        </tbody>
      </table>
    </Card>
  );
}

export function McHealthPanel(props: {
  data: McHealthData | null;
  token: string | null;
  location?: string;
}) {
  const { data } = props;
  if (!data)
    return (
      <div className="stat-empty">Waiting for the server's numbers...</div>
    );
  return (
    <div className="mch">
      <Health data={data} />
      <Ticks data={data} />
      <Uses data={data} />
      <Overruns data={data} />
      <Memory data={data} />
      <Entities data={data} />
      <Native data={data} />
      <Advanced data={data} location={props.location} />
    </div>
  );
}
