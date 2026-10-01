// SVG charts: a multi-series line chart with a crosshair tooltip, a horizontal bar list with a
// baseline marker, a stacked column chart and a sparkline. Series take palette slots in fixed
// order (series-1..8), lines are 2px, one y-axis per chart.

import { type ReactNode, useId, useMemo, useRef, useState } from 'react';

export const SLOT = (i: number) => `var(--series-${(i % 8) + 1})`;

export function fmt(v: number | null | undefined, unit = ''): string {
  if (v === null || v === undefined || Number.isNaN(v)) return '–';
  const abs = Math.abs(v);
  const digits = abs >= 100 ? 0 : abs >= 10 ? 1 : abs >= 1 ? 2 : 3;
  const n = v.toLocaleString(undefined, { maximumFractionDigits: digits });
  if (!unit) return n;
  if (unit === '%') return `${n}%`;
  return `${n} ${unit}`;
}

export function fmtDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return '–';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600)
    return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`;
}

const timeLabel = (ms: number, span: number) =>
  new Date(ms).toLocaleString(
    undefined,
    span > 2 * 86_400_000
      ? { month: 'short', day: 'numeric' }
      : { hour: '2-digit', minute: '2-digit' },
  );

/** Round-number ticks covering [min, max]. */
function niceTicks(min: number, max: number, count = 4, minSpan = 1): number[] {
  if (max - min < minSpan) max = min + minSpan;
  const raw = (max - min) / count;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step =
    [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? raw;
  const out: number[] = [];
  let v = Math.floor(min / step) * step;
  out.push(Number(v.toFixed(10)));
  // Keep stepping until the top tick covers the maximum, so nothing is drawn above the plot.
  while (v < max - step * 1e-6) {
    v += step;
    out.push(Number(v.toFixed(10)));
  }
  return out;
}

export type Series = {
  name: string;
  points: [number, number][];
  color?: string;
};

/** Lines over time (x = epoch ms) or over an index (x = 0..n-1 with `xLabels`). */
export function LineChart({
  series,
  unit = '',
  height = 200,
  xLabels,
  zeroBased = true,
  markers = false,
}: {
  series: Series[];
  unit?: string;
  height?: number;
  xLabels?: string[];
  zeroBased?: boolean;
  markers?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const clipId = useId();
  const [hover, setHover] = useState<number | null>(null);
  const width = 640;
  const pad = { l: 44, r: 10, t: 8, b: 22 };
  const xs = useMemo(
    () =>
      [...new Set(series.flatMap((s) => s.points.map((p) => p[0])))].sort(
        (a, b) => a - b,
      ),
    [series],
  );
  if (!xs.length) return <div className="empty">No data yet.</div>;
  const ys = series.flatMap((s) => s.points.map((p) => p[1]));
  const yMin = zeroBased ? Math.min(0, ...ys) : Math.min(...ys);
  const ticks = niceTicks(yMin, Math.max(...ys, yMin + 1e-9));
  const y0 = ticks[0];
  const y1 = ticks[ticks.length - 1];
  const x0 = xs[0];
  const x1 = xs[xs.length - 1] === x0 ? x0 + 1 : xs[xs.length - 1];
  const X = (x: number) =>
    pad.l + ((x - x0) / (x1 - x0)) * (width - pad.l - pad.r);
  const Y = (y: number) =>
    pad.t + (1 - (y - y0) / (y1 - y0 || 1)) * (height - pad.t - pad.b);
  const span = x1 - x0;
  const xTickCount = Math.min(xLabels ? 5 : 6, xs.length);
  const xTicks = Array.from(
    { length: xTickCount },
    (_, i) =>
      xs[Math.round((i * (xs.length - 1)) / Math.max(xTickCount - 1, 1))],
  );
  const clip = (t: string) => (t.length > 16 ? `${t.slice(0, 15)}…` : t);
  const label = (x: number) =>
    xLabels ? clip(xLabels[x] ?? '') : timeLabel(x, span);
  const fullLabel = (x: number) =>
    xLabels ? (xLabels[x] ?? '') : new Date(x).toLocaleString();

  const onMove = (e: React.MouseEvent) => {
    const box = ref.current?.getBoundingClientRect();
    if (!box) return;
    const px = ((e.clientX - box.left) / box.width) * width;
    const target = x0 + ((px - pad.l) / (width - pad.l - pad.r)) * (x1 - x0);
    let best = xs[0];
    for (const x of xs)
      if (Math.abs(x - target) < Math.abs(best - target)) best = x;
    setHover(best);
  };
  const hoverLeft = hover !== null ? (X(hover) / width) * 100 : 0;

  return (
    <div
      className="chart"
      ref={ref}
      onMouseMove={onMove}
      onMouseLeave={() => setHover(null)}
    >
      {series.length > 1 && (
        <div className="legend">
          {series.map((s, i) => (
            <span key={s.name}>
              <i style={{ background: s.color ?? SLOT(i) }} />
              {s.name}
            </span>
          ))}
        </div>
      )}
      <svg
        viewBox={`0 0 ${width} ${height}`}
        role="img"
        aria-label={series.map((s) => s.name).join(', ')}
      >
        <defs>
          <clipPath id={clipId}>
            <rect
              x={pad.l - 4}
              y={pad.t - 4}
              width={width - pad.l - pad.r + 8}
              height={height - pad.t - pad.b + 8}
            />
          </clipPath>
        </defs>
        <g className="grid">
          {ticks.map((t) => (
            <line key={t} x1={pad.l} x2={width - pad.r} y1={Y(t)} y2={Y(t)} />
          ))}
        </g>
        <g className="axis">
          {ticks.map((t) => (
            <text key={t} x={pad.l - 6} y={Y(t) + 4} textAnchor="end">
              {fmt(t, unit === '%' ? '%' : '')}
            </text>
          ))}
          {xTicks.map((x, i) => (
            <text
              key={`${x}-${i}`}
              x={X(x)}
              y={height - 4}
              textAnchor={
                i === 0 ? 'start' : i === xTicks.length - 1 ? 'end' : 'middle'
              }
            >
              {label(x)}
            </text>
          ))}
        </g>
        {series.map((s, i) => (
          <g key={s.name} clipPath={`url(#${clipId})`}>
            <path
              d={s.points
                .map(
                  (p, j) =>
                    `${j ? 'L' : 'M'}${X(p[0]).toFixed(1)},${Y(p[1]).toFixed(1)}`,
                )
                .join('')}
              fill="none"
              stroke={s.color ?? SLOT(i)}
              strokeWidth={2}
              strokeLinejoin="round"
              strokeLinecap="round"
            />
            {markers &&
              s.points.map((p) => (
                <circle
                  key={p[0]}
                  cx={X(p[0])}
                  cy={Y(p[1])}
                  r={3.5}
                  fill={s.color ?? SLOT(i)}
                  stroke="var(--surface-1)"
                  strokeWidth={2}
                />
              ))}
          </g>
        ))}
        {hover !== null && (
          <g>
            <line
              x1={X(hover)}
              x2={X(hover)}
              y1={pad.t}
              y2={height - pad.b}
              stroke="var(--text-muted)"
              strokeDasharray="3 3"
            />
            {series.map((s, i) => {
              const p = s.points.find((q) => q[0] === hover);
              return p ? (
                <circle
                  key={s.name}
                  cx={X(p[0])}
                  cy={Y(p[1])}
                  r={4}
                  fill={s.color ?? SLOT(i)}
                  stroke="var(--surface-1)"
                  strokeWidth={2}
                />
              ) : null;
            })}
          </g>
        )}
      </svg>
      {hover !== null && (
        <div
          className="tooltip"
          style={{ left: `${Math.min(hoverLeft, 70)}%`, top: 24 }}
        >
          <div className="t">{fullLabel(hover)}</div>
          {series.map((s, i) => {
            const p = s.points.find((q) => q[0] === hover);
            return p ? (
              <div className="row" key={s.name}>
                <i style={{ background: s.color ?? SLOT(i) }} />
                {s.name}
                <b>{fmt(p[1], unit)}</b>
              </div>
            ) : null;
          })}
        </div>
      )}
    </div>
  );
}

export type BarRow = {
  key: string;
  label: ReactNode;
  value: number;
  baseline?: number | null;
  outlier?: boolean;
  title?: string;
};

/** Horizontal bars, largest first, with each row's baseline drawn as a tick. */
export function BarList({
  rows,
  unit = '',
  onSelect,
  selected,
  limit = 30,
}: {
  rows: BarRow[];
  unit?: string;
  onSelect?: (key: string) => void;
  selected?: string;
  limit?: number;
}) {
  const shown = rows.slice(0, limit);
  const max = Math.max(
    ...shown.map((r) => Math.max(r.value, r.baseline ?? 0)),
    1e-9,
  );
  if (!shown.length) return <div className="empty">Nothing recorded.</div>;
  return (
    <div className="barlist">
      {shown.map((r) => (
        <div
          key={r.key}
          className={`row${r.outlier ? ' out' : ''}${selected === r.key ? ' sel' : ''}`}
          onClick={() => onSelect?.(r.key)}
          title={r.title}
        >
          <div className="name">{r.label}</div>
          <div className="track">
            <div
              className="bar"
              style={{ width: `${Math.max((r.value / max) * 100, 0.5)}%` }}
            />
            {r.baseline !== null && r.baseline !== undefined && (
              <div
                className="base"
                style={{ left: `calc(${(r.baseline / max) * 100}% - 1px)` }}
              />
            )}
          </div>
          <div className="val">{fmt(r.value, unit)}</div>
        </div>
      ))}
      {rows.length > limit && (
        <div className="muted" style={{ padding: '6px 4px' }}>
          …and {rows.length - limit} more
        </div>
      )}
    </div>
  );
}

/** Stacked columns per x label (e.g. tickets per day by level). */
export function StackedColumns({
  labels,
  series,
  height = 160,
}: {
  labels: string[];
  series: { name: string; values: number[] }[];
  height?: number;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const width = 640;
  const pad = { l: 32, r: 6, t: 8, b: 20 };
  const totals = labels.map((_, i) =>
    series.reduce((a, s) => a + (s.values[i] ?? 0), 0),
  );
  const ticks = niceTicks(0, Math.max(...totals, 1), 3);
  const top = ticks[ticks.length - 1];
  const band = (width - pad.l - pad.r) / Math.max(labels.length, 1);
  const barW = Math.max(band - 2, 1);
  const Y = (v: number) => pad.t + (1 - v / top) * (height - pad.t - pad.b);
  return (
    <div className="chart" onMouseLeave={() => setHover(null)}>
      <div className="legend">
        {series.map((s, i) => (
          <span key={s.name}>
            <i style={{ background: SLOT(i) }} />
            {s.name}
          </span>
        ))}
      </div>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        role="img"
        aria-label={series.map((s) => s.name).join(', ')}
      >
        <g className="grid">
          {ticks.map((t) => (
            <line key={t} x1={pad.l} x2={width - pad.r} y1={Y(t)} y2={Y(t)} />
          ))}
        </g>
        <g className="axis">
          {ticks.map((t) => (
            <text key={t} x={pad.l - 6} y={Y(t) + 4} textAnchor="end">
              {t}
            </text>
          ))}
          {labels.map((l, i) =>
            i % Math.ceil(labels.length / 7) === 0 ? (
              <text
                key={l}
                x={pad.l + i * band + band / 2}
                y={height - 4}
                textAnchor="middle"
              >
                {l.slice(5)}
              </text>
            ) : null,
          )}
        </g>
        {labels.map((l, i) => {
          let acc = 0;
          return (
            <g key={l} onMouseEnter={() => setHover(i)}>
              <rect
                x={pad.l + i * band}
                y={pad.t}
                width={band}
                height={height - pad.t - pad.b}
                fill="transparent"
              />
              {series.map((s, si) => {
                const v = s.values[i] ?? 0;
                if (!v) return null;
                const y = Y(acc + v);
                const h = Y(acc) - y;
                acc += v;
                return (
                  <rect
                    key={s.name}
                    x={pad.l + i * band + 1}
                    y={y}
                    width={barW}
                    height={Math.max(h - 2, 1)}
                    rx={2}
                    fill={SLOT(si)}
                  />
                );
              })}
            </g>
          );
        })}
      </svg>
      {hover !== null && (
        <div
          className="tooltip"
          style={{
            left: `${Math.min(((pad.l + hover * band) / width) * 100, 72)}%`,
            top: 24,
          }}
        >
          <div className="t">{labels[hover]}</div>
          {series.map((s, i) => (
            <div className="row" key={s.name}>
              <i style={{ background: SLOT(i) }} />
              {s.name}
              <b>{s.values[hover] ?? 0}</b>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/** A tiny trend line; the last point is marked. */
export function Sparkline({
  values,
  width = 110,
  height = 24,
}: {
  values: number[];
  width?: number;
  height?: number;
}) {
  if (!values.length) return null;
  const max = Math.max(...values, 1e-9);
  const X = (i: number) =>
    (i / Math.max(values.length - 1, 1)) * (width - 4) + 2;
  const Y = (v: number) => height - 2 - (v / max) * (height - 4);
  return (
    <svg width={width} height={height} role="img" aria-label="trend">
      <path
        d={values.map((v, i) => `${i ? 'L' : 'M'}${X(i)},${Y(v)}`).join('')}
        fill="none"
        stroke="var(--series-1)"
        strokeWidth={1.5}
      />
      <circle
        cx={X(values.length - 1)}
        cy={Y(values[values.length - 1])}
        r={2.5}
        fill="var(--series-1)"
      />
    </svg>
  );
}

/** A status badge: colour plus a label, never colour alone. */
export function Badge({
  kind,
  children,
}: {
  kind: 'critical' | 'serious' | 'warning' | 'good' | 'info';
  children: ReactNode;
}) {
  return (
    <span className={`badge ${kind}`}>
      <span className="dot" />
      {children}
    </span>
  );
}
