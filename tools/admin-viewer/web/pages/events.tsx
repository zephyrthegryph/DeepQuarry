import { useState } from 'react';
import {
  Badge,
  BarList,
  fmt,
  fmtDuration,
  Sparkline,
  StackedColumns,
} from '../charts';
import {
  Card,
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

const DAY_OPTIONS = [
  { id: '1', label: '24h' },
  { id: '7', label: '7d' },
  { id: '30', label: '30d' },
  { id: '90', label: '90d' },
];

type RuntimeGroup = {
  signature: string;
  message: string;
  location: string;
  /** The proc it happened in, and the call stack of its first sighting (newest flush). */
  proc: string | null;
  stack: string[];
  total: number;
  rounds: number;
  first_seen: string;
  last_seen: string;
  is_new: boolean;
  link: string | null;
  daily: number[];
};

export function RuntimesPage({ params }: PageProps) {
  const [days, setDays] = useState(params.get('days') ?? '7');
  const [includeTests, setIncludeTests] = useIncludeTests();
  const data = useApi<{ days: string[]; groups: RuntimeGroup[] }>(
    `/api/runtimes?days=${days}${testsParam(includeTests)}`,
    60_000,
  );
  const [open, setOpen] = useState<string | null>(null);
  const groups = data.data?.groups ?? [];
  const total = groups.reduce((a, g) => a + g.total, 0);
  return (
    <>
      <div className="page-head">
        <h1>Runtimes</h1>
        <div className="filters">
          <TestRoundsToggle value={includeTests} onChange={setIncludeTests} />
          <Seg value={days} options={DAY_OPTIONS} onChange={setDays} />
        </div>
      </div>
      <div className="tiles">
        <Tile
          label="Runtimes"
          value={fmt(total)}
          note={`last ${days} day(s)`}
        />
        <Tile label="Distinct errors" value={fmt(groups.length)} />
        <Tile
          label="New in the last 24h"
          value={fmt(groups.filter((g) => g.is_new).length)}
        />
      </div>
      <Card
        title="Grouped by error"
        sub="Same file, line and message grouped together, most frequent first. The sparkline is per day; click a row for its call stack."
      >
        {!data.data ? (
          <Loading error={data.error} />
        ) : !groups.length ? (
          <div className="empty">No runtimes recorded in this period.</div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Error</th>
                  <th>Where</th>
                  <th className="num">Count</th>
                  <th className="num">Rounds</th>
                  <th>First seen</th>
                  <th>Last seen</th>
                  <th>Per day</th>
                </tr>
              </thead>
              <tbody>
                {groups.map((g) => (
                  <tr
                    key={g.signature}
                    className="click"
                    onClick={() =>
                      setOpen(open === g.signature ? null : g.signature)
                    }
                  >
                    <td style={{ maxWidth: 420, whiteSpace: 'normal' }}>
                      {g.is_new && <Badge kind="warning">new</Badge>}{' '}
                      {g.message}
                      {g.proc && g.proc !== g.location && (
                        <div className="sub mono">in {g.proc}</div>
                      )}
                      {open === g.signature &&
                        (g.stack.length ? (
                          <ol className="stack mono">
                            {g.stack.map((line, i) => (
                              <li key={i}>{line}</li>
                            ))}
                          </ol>
                        ) : (
                          <div className="sub">No call stack recorded.</div>
                        ))}
                    </td>
                    <td className="mono">
                      {g.link ? (
                        <a
                          href={g.link}
                          target="_blank"
                          rel="noreferrer"
                          onClick={(e) => e.stopPropagation()}
                        >
                          {g.location}
                        </a>
                      ) : (
                        g.location
                      )}
                    </td>
                    <td className="num">{fmt(g.total)}</td>
                    <td className="num">{g.rounds}</td>
                    <td>{when(g.first_seen)}</td>
                    <td>{when(g.last_seen)}</td>
                    <td>
                      <Sparkline values={g.daily} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}

type Overrun = {
  round_id: number;
  ts: string;
  top: string;
  usage: number;
  maptick: number;
  streak: number;
  pre_mc: number | null;
  post_mc: number | null;
  breakdown: { name: string; usage: number }[];
  top_systems: { key: string; ms: number }[];
  /** The one entity step that took most of the tick, when one took over a tick by itself. */
  slow_step: {
    kind?: string;
    behaviour: string;
    entity: string;
    name: string;
    ms: number;
  } | null;
};

type Profile = {
  round_id: number;
  ts: string;
  reason: string;
  message: string;
  from_t: number;
  to_t: number;
  self_total?: number;
  procs?: number;
  top: {
    name: string;
    self: number;
    total: number;
    real: number;
    calls: number;
  }[];
  spike?: { t: number; usage: number; cause: string };
  om_types?: { behaviour: string; type: string; ms: number }[];
};

export function OverrunsPage({ params }: PageProps) {
  const [days, setDays] = useState(params.get('days') ?? '7');
  const [includeTests, setIncludeTests] = useIncludeTests();
  const data = useApi<{
    events: Overrun[];
    by_top: { name: string; count: number; worst: number }[];
    profiles: Profile[];
  }>(`/api/overruns?days=${days}${testsParam(includeTests)}`, 60_000);
  const [open, setOpen] = useState<number | null>(null);
  const [openProfile, setOpenProfile] = useState<number | null>(0);
  return (
    <>
      <div className="page-head">
        <h1>Tick overruns</h1>
        <div className="filters">
          <TestRoundsToggle value={includeTests} onChange={setIncludeTests} />
          <Seg value={days} options={DAY_OPTIONS} onChange={setDays} />
        </div>
      </div>
      {!data.data ? (
        <Loading error={data.error} />
      ) : (
        <div className="grid cols-2">
          <Card
            title="What was running"
            sub="What took most of each recorded overrun tick: a subsystem, an object-model system, or Outside MC (time before or after the MC's own run: resumed sleeping procs, verbs, Topic). The worst few per minute are kept in full."
          >
            <BarList
              rows={data.data.by_top.map((t) => ({
                key: t.name,
                label: t.name,
                value: t.count,
                title: `worst ${fmt(t.worst, '%')}`,
              }))}
            />
          </Card>
          <Card
            title="Worst ticks"
            sub="Newest first; click one for where its time went."
          >
            {!data.data.events.length ? (
              <div className="empty">No overruns recorded in this period.</div>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>When</th>
                      <th>Round</th>
                      <th className="num">Tick usage</th>
                      <th>Cause</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.data.events.slice(0, 60).map((e, i) => (
                      <tr
                        key={`${e.ts}-${i}`}
                        className={`click${open === i ? ' sel' : ''}`}
                        onClick={() => setOpen(open === i ? null : i)}
                      >
                        <td>{when(e.ts)}</td>
                        <td>{e.round_id}</td>
                        <td className="num">
                          <Badge kind={e.usage >= 200 ? 'critical' : 'serious'}>
                            {fmt(e.usage, '%')}
                          </Badge>
                        </td>
                        <td>
                          {e.top}
                          {open === i && (
                            <ul className="breakdown">
                              {[...e.breakdown]
                                .sort((a, b) => b.usage - a.usage)
                                .slice(0, 8)
                                .map((b) => (
                                  <li key={b.name}>
                                    {b.name}: {fmt(b.usage, '%')}
                                  </li>
                                ))}
                              {e.top_systems.map((t) => (
                                <li key={`sys-${t.key}`}>
                                  system {t.key}: {fmt(t.ms, 'ms')}
                                </li>
                              ))}
                              {e.slow_step && (
                                <li>
                                  slowest {e.slow_step.kind ?? 'step'}:{' '}
                                  {e.slow_step.behaviour} on {e.slow_step.name}{' '}
                                  ({e.slow_step.entity}),{' '}
                                  {fmt(e.slow_step.ms, 'ms')}
                                </li>
                              )}
                              {e.post_mc ? (
                                <li>after the MC: {fmt(e.post_mc, '%')}</li>
                              ) : null}
                            </ul>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
          <Card
            title="Profiles"
            sub="BYOND proc profiles the server took: the first minute of each round, 30 s of steady play, and a few seconds after a tick far over budget. Procs by self time, then the object-model work by behaviour and entity type."
          >
            {!data.data.profiles.length ? (
              <div className="empty">No profiles in this period.</div>
            ) : (
              data.data.profiles.map((p, i) => (
                <div key={`${p.ts}-${i}`} className="profile">
                  <button
                    type="button"
                    className="linkish"
                    onClick={() => setOpenProfile(openProfile === i ? null : i)}
                  >
                    Round {p.round_id} · {when(p.ts)} · {p.message}
                  </button>
                  {openProfile === i && p.self_total ? (
                    <div className="sub">
                      All DM procs: {fmt(p.self_total, 'ms')} self time over{' '}
                      {fmt(p.to_t - p.from_t)} s ({fmt(p.procs)} procs).
                    </div>
                  ) : null}
                  {openProfile === i && (
                    <div className="table-wrap">
                      <table>
                        <thead>
                          <tr>
                            <th>Proc</th>
                            <th className="num">Self</th>
                            <th className="num">Total</th>
                            <th className="num">Calls</th>
                          </tr>
                        </thead>
                        <tbody>
                          {p.top.map((r) => (
                            <tr key={r.name}>
                              <td className="mono">{r.name}</td>
                              <td className="num">{fmt(r.self, 'ms')}</td>
                              <td className="num">{fmt(r.total, 'ms')}</td>
                              <td className="num">{fmt(r.calls)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                  {openProfile === i && p.om_types?.length ? (
                    <div className="table-wrap">
                      <table>
                        <thead>
                          <tr>
                            <th>Behaviour</th>
                            <th>Entity type</th>
                            <th className="num">Time</th>
                          </tr>
                        </thead>
                        <tbody>
                          {p.om_types.map((r) => (
                            <tr key={`${r.behaviour}|${r.type}`}>
                              <td>{r.behaviour}</td>
                              <td className="mono">{r.type}</td>
                              <td className="num">{fmt(r.ms, 'ms')}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  ) : null}
                </div>
              ))
            )}
          </Card>
        </div>
      )}
    </>
  );
}

type StaffData = {
  totals: { tickets: number; unhandled: number; handled: number };
  time_to_handle: { median: number; p90: number; n: number };
  time_to_close: { median: number; p90: number; n: number };
  per_day: { day: string; admin: number; mentor: number }[];
  handlers: { ckey: string; n: number }[];
  recent_tickets: {
    key: string;
    round_id: number;
    id: string;
    ckey: string;
    title: string;
    level: string;
    handled_s?: number;
    handler?: string;
    closed_s?: number;
    outcome?: string;
  }[];
  verbs: { verb: string; category: string; n: number; admins: number }[];
  admins: { ckey: string; n: number; rounds: number; last: string }[];
  recent_verbs: {
    ts: string;
    ckey: string;
    message: string;
    category: string;
    round_id: number;
  }[];
};

export function StaffPage({ params }: PageProps) {
  const [days, setDays] = useState(params.get('days') ?? '30');
  const data = useApi<StaffData>(`/api/staff?days=${days}`, 60_000);
  if (!data.data) return <Loading error={data.error} />;
  const d = data.data;
  return (
    <>
      <div className="page-head">
        <h1>Staff &amp; tickets</h1>
        <div className="filters">
          <Seg value={days} options={DAY_OPTIONS} onChange={setDays} />
        </div>
      </div>
      <div className="tiles">
        <Tile label="Tickets" value={fmt(d.totals.tickets)} />
        <Tile label="Never handled" value={fmt(d.totals.unhandled)} />
        <Tile
          label="Time to handle (median)"
          value={fmtDuration(d.time_to_handle.median)}
          note={`p90 ${fmtDuration(d.time_to_handle.p90)}`}
        />
        <Tile
          label="Time to close (median)"
          value={fmtDuration(d.time_to_close.median)}
          note={`p90 ${fmtDuration(d.time_to_close.p90)}`}
        />
        <Tile
          label="Admin verbs used"
          value={fmt(d.verbs.reduce((a, v) => a + v.n, 0))}
        />
      </div>
      <div className="grid cols-2">
        <Card title="Tickets per day" sub="Admin and mentor helps opened.">
          <StackedColumns
            labels={d.per_day.map((p) => p.day)}
            series={[
              { name: 'Admin', values: d.per_day.map((p) => p.admin) },
              { name: 'Mentor', values: d.per_day.map((p) => p.mentor) },
            ]}
          />
        </Card>
        <Card title="Most used admin verbs">
          <BarList
            rows={d.verbs.map((v) => ({
              key: `${v.verb}|${v.category}`,
              label: v.verb,
              value: v.n,
              title: `${v.category}: used by ${v.admins} admin(s)`,
            }))}
            limit={15}
          />
        </Card>
        <Card title="Recent tickets">
          {!d.recent_tickets.length ? (
            <div className="empty">No tickets in this period.</div>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Round · #</th>
                    <th>From</th>
                    <th>Title</th>
                    <th>Handled by</th>
                    <th className="num">To handle</th>
                    <th>Outcome</th>
                  </tr>
                </thead>
                <tbody>
                  {d.recent_tickets.map((t) => (
                    <tr key={t.key}>
                      <td>
                        {t.round_id} · {t.id}
                      </td>
                      <td>{t.ckey}</td>
                      <td>{t.title}</td>
                      <td>
                        {t.handler ?? <span className="muted">nobody</span>}
                      </td>
                      <td className="num">{fmtDuration(t.handled_s)}</td>
                      <td>
                        {t.outcome ? (
                          <Badge
                            kind={t.outcome === 'resolved' ? 'good' : 'info'}
                          >
                            {t.outcome}
                          </Badge>
                        ) : (
                          <Badge kind="warning">open</Badge>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
        <Card title="Admin activity">
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Admin</th>
                  <th className="num">Verbs</th>
                  <th className="num">Rounds</th>
                  <th>Last active</th>
                  <th className="num">Tickets handled</th>
                </tr>
              </thead>
              <tbody>
                {d.admins.map((a) => (
                  <tr key={a.ckey}>
                    <td>{a.ckey}</td>
                    <td className="num">{a.n}</td>
                    <td className="num">{a.rounds}</td>
                    <td>{when(a.last)}</td>
                    <td className="num">
                      {d.handlers.find((h) => h.ckey === a.ckey)?.n ?? 0}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
        <Card title="Admin verb log" sub="Every admin verb, newest first.">
          <div className="table-wrap" style={{ maxHeight: 360 }}>
            <table>
              <thead>
                <tr>
                  <th>When</th>
                  <th>Admin</th>
                  <th>Verb</th>
                  <th>Category</th>
                  <th>Round</th>
                </tr>
              </thead>
              <tbody>
                {d.recent_verbs.map((v, i) => (
                  <tr key={`${v.ts}-${i}`}>
                    <td>{when(v.ts)}</td>
                    <td>{v.ckey}</td>
                    <td>{v.message}</td>
                    <td className="muted">{v.category}</td>
                    <td>{v.round_id}</td>
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
