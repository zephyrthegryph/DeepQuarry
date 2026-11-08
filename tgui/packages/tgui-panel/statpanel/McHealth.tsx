/**
 * The MC Health panel: the Health page of the stat panel's Server view. One page built around what is using the tick: the
 * tick now, its consumers, the overruns ranked by size and the recent ticks; everything else is in closed sections. The server sends its data
 * (code/content/client/mc_health.dm) only while this page is open, at most once a second. Sections remember open/closed per admin.
 */

import { memo, type ReactNode, useMemo, useState } from 'react';
import {
  averageTickParts,
  bytes,
  count,
  framePhases,
  histogramPercentile,
  type McHealthData,
  nativeMemoryByArea,
  nativeWork,
  overrunParts,
  overrunSummary,
  perMinute,
  type RecentTick,
  systemsByCost,
  type TickPart,
  tickParts,
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
  return (
    <div className="mch-health">
      <div className="mch-headline">
        <b className={`mch-big mch-big--${verdict.level}`}>{pct(w.avg)}</b>
        <div>
          <div>of each tick in use</div>
          <span className={`mch-pill mch-pill--${verdict.level}`}>
            {verdict.label}
          </span>
        </div>
      </div>
      <div className="mch-gauge" title={verdict.why}>
        <div
          className={`mch-gauge__fill mch-gauge__fill--${verdict.level}`}
          style={{ width: `${use}%` }}
        />
      </div>
      <div className="mch-facts">
        {w.tps.toFixed(1)}/{data.target_tps} tps · slowdown {pct(data.tidi, 1)}{' '}
        · {count(data.window_5m.overruns)} overruns in 5 min
      </div>
    </div>
  );
}

/** Consumers as ranked bars, each as long as its share of the largest total; the first is the answer to "what is using the tick?". */
function PartBars(props: { parts: TickPart[]; total?: number }) {
  const total =
    props.total ?? props.parts.reduce((sum, part) => sum + part.ms, 0);
  return (
    <div className="mch-parts">
      {props.parts.map((part) => (
        <div
          key={part.name}
          className={`mch-part${part.unknown ? ' mch-part--unknown' : ''}`}
          title={part.name}
        >
          <div
            className="mch-part__fill"
            style={{ width: `${total > 0 ? (part.ms / total) * 100 : 0}%` }}
          />
          <span className="mch-part__name">{part.name}</span>
          <span className="mch-part__ms">{part.ms.toFixed(1)} ms</span>
        </div>
      ))}
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
  // The bars hold still under the mouse: the page keeps drawing the ticks it had when the mouse came in, until it leaves.
  const [frozen, setFrozen] = useState<RecentTick[] | null>(null);
  const [pinned, setPinned] = useState<RecentTick | null>(null);
  const [hover, setHover] = useState<RecentTick | null>(null);
  const ticks = frozen ?? (data.ticks || []);
  const top = Math.max(120, ...ticks.map((t) => t[0]));
  const tick = hover ?? pinned;
  return (
    <Card
      id="ticks"
      title="Recent ticks"
      summary={frozen ? 'held while you read' : `last ${ticks.length}`}
    >
      <div
        className="mch-timeline"
        onMouseEnter={() => setFrozen(data.ticks || [])}
        onMouseLeave={() => {
          setFrozen(null);
          setHover(null);
        }}
      >
        <div
          className="mch-budget"
          style={{ bottom: `${(100 / top) * 100}%` }}
          title={`budget ${data.tick_budget_ms} ms`}
        />
        {ticks.map((t, i) => (
          <div
            key={i}
            className={`mch-bar${t[0] > 100 ? ' mch-bar--over' : ''}${t === pinned ? ' mch-bar--pinned' : ''}`}
            style={{ height: `${(t[0] / top) * 100}%` }}
            onMouseEnter={() => setHover(t)}
            onClick={() => setPinned(t === pinned ? null : t)}
          />
        ))}
      </div>
      <div className="mch-tickdetail">
        {tick ? (
          <>
            <div className="mch-tickuse">
              {pct(tick[0], 1)} of the tick
              {tick === pinned && !hover ? ' (pinned)' : ''}
            </div>
            <PartBars parts={tickParts(tick, data.tick_budget_ms)} />
          </>
        ) : (
          <span className="mch-muted">
            Hover a bar to see that tick; click to pin it.
          </span>
        )}
      </div>
    </Card>
  );
}

function Distribution({ data }: { data: McHealthData }) {
  const [win, setWin] = useState<'5s' | '30s' | '5m'>('5s');
  const w = {
    '5s': data.window_5s,
    '30s': data.window_30s,
    '5m': data.window_5m,
  }[win];
  return (
    <Card id="dist" title="Tick distribution" closed>
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
  const [expanded, setExpanded] = useState<string | null>(null);
  const systems = systemsByCost(data.kernel?.systems);
  const parts = averageTickParts(
    systems,
    data.window_30s.avg,
    data.tick_budget_ms,
    data.window_30s.tps || data.target_tps,
  );
  const total = parts.reduce((sum, part) => sum + part.ms, 0);
  const rows = all ? parts : parts.slice(0, 6);
  const biggest = parts[0];
  return (
    <Card
      id="where"
      title="What uses the tick"
      summary={biggest ? `${biggest.name} first` : undefined}
    >
      {rows.map((part) => {
        const behind =
          data.attribution?.[part.name] ?? data.attribution_rest?.[part.name];
        const isOpen = expanded === part.name;
        return (
          <div
            key={part.name}
            className={behind ? 'mch-row--expandable' : undefined}
            onClick={() => behind && setExpanded(isOpen ? null : part.name)}
          >
            <PartBars parts={[part]} total={total} />
            {isOpen &&
              behind?.map(([source, kind, n, totalMs, maxMs]) => (
                <div key={source} className="mch-behind" title={kind}>
                  <span>{source}</span>
                  <span>
                    {count(n)}× · {totalMs.toFixed(1)} ms · max{' '}
                    {maxMs.toFixed(1)} ms
                  </span>
                </div>
              ))}
          </div>
        );
      })}
      {parts.length > 6 && (
        <button type="button" className="mch-link" onClick={() => setAll(!all)}>
          {all ? 'Show the top 6' : `Show all ${parts.length}`}
        </button>
      )}
    </Card>
  );
}

function Overruns({ data }: { data: McHealthData }) {
  const [open, setOpen] = useState<number | null>(null);
  const outliers = (data.outliers || [])
    .filter((o) => o.usage > 100)
    .sort((a, b) => b.overrun - a.overrun);
  return (
    <Card
      id="ovr"
      title="Overruns"
      summary={`${data.window_5m.overruns} in 5 min, worst first`}
    >
      {outliers.length === 0 && (
        <div className="mch-muted">
          {overrunSummary(outliers, data.window_5m)}
        </div>
      )}
      {outliers.map((o) => {
        const parts = overrunParts(o, data.tick_budget_ms);
        const isOpen = open === o.world_time;
        return (
          <div
            key={`${o.world_time}:${o.usage}`}
            className="mch-overrun"
            onClick={() => setOpen(isOpen ? null : o.world_time)}
          >
            <div className="mch-overrun__head">
              <b>+{o.overrun.toFixed(0)}%</b>
              <span className="mch-overrun__top">
                {parts[0]?.name ?? o.cause ?? 'Unknown'}
              </span>
              <span className="mch-muted">
                {(o.world_time / 10).toFixed(0)} s
              </span>
            </div>
            {isOpen && <PartBars parts={parts} />}
            {!isOpen && parts[0] && (
              <PartBars
                parts={parts.slice(0, 1)}
                total={parts.reduce((sum, part) => sum + part.ms, 0)}
              />
            )}
          </div>
        );
      })}
    </Card>
  );
}

function Memory({ data }: { data: McHealthData }) {
  const rust = data.rust || {};
  const total = rust['process.working_set_bytes'];
  const native = rust['alloc.heap.current_bytes'];
  const gc = data.gc;
  return (
    <Card
      id="mem"
      title="Memory"
      summary={total ? bytes(total) : undefined}
      closed
    >
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
      closed
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
      <Card id="rust" title="Native (Rust)" closed>
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
    <Card
      id="rust"
      title="Native (Rust)"
      summary={`frame ${us(avg)} avg`}
      closed
    >
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
  token: string | null;
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
        {(['kernel', 'globals', 'config'] as const).map((name) => (
          <a
            key={name}
            href={`byond://?_src_=holder;admin_token=${props.token};mc_vv=${name}`}
          >
            View {name[0].toUpperCase() + name.slice(1)} vars
          </a>
        ))}
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

/**
 * The data a section reads, as one object that keeps its identity while those slices do: the server sends only the sections that changed and
 * the store keeps the others' objects, so a memoized section whose slices are unchanged does not render again (renderCost.test.tsx).
 */
function useSlices(
  data: McHealthData | null,
  keys: (keyof McHealthData)[],
): McHealthData | null {
  const deps = keys.map((key) => data?.[key]);
  return useMemo(() => {
    if (!data) return null;
    const out: Record<string, unknown> = {};
    for (const key of keys) out[key] = data[key];
    return out as McHealthData;
  }, deps);
}

const UsesMemo = memo(Uses);
const OverrunsMemo = memo(Overruns);
const MemoryMemo = memo(Memory);
const EntitiesMemo = memo(Entities);
const NativeMemo = memo(Native);
const AdvancedMemo = memo(Advanced);

export function McHealthPanel(props: {
  data: McHealthData | null;
  token: string | null;
  location?: string;
}) {
  const { data } = props;
  const uses = useSlices(data, [
    'kernel',
    'attribution',
    'attribution_rest',
    'window_30s',
    'tick_budget_ms',
    'target_tps',
  ]);
  const overruns = useSlices(data, ['outliers', 'window_5m', 'tick_budget_ms']);
  const memory = useSlices(data, ['rust', 'gc']);
  const entities = useSlices(data, ['entities', 'churn']);
  const native = useSlices(data, ['rust']);
  const advanced = useSlices(data, ['runtime', 'kernel', 'maptick']);
  if (
    !data ||
    !uses ||
    !overruns ||
    !memory ||
    !entities ||
    !native ||
    !advanced
  )
    return (
      <div className="stat-empty">Waiting for the server's numbers...</div>
    );
  return (
    <div className="mch">
      <Health data={data} />
      <UsesMemo data={uses} />
      <OverrunsMemo data={overruns} />
      <Ticks data={data} />
      <Distribution data={data} />
      <MemoryMemo data={memory} />
      <EntitiesMemo data={entities} />
      <NativeMemo data={native} />
      <AdvancedMemo
        data={advanced}
        token={props.token}
        location={props.location}
      />
    </div>
  );
}
