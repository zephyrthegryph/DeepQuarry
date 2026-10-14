import { type ReactNode, useEffect, useState } from 'react';

export type PageProps = { params: URLSearchParams };

/** Fetches a JSON endpoint; refetches when the URL changes and, with `refreshMs`, on a timer. */
export function useApi<T>(
  url: string | null,
  refreshMs = 0,
): { data: T | null; error: string | null; loading: boolean } {
  const [state, setState] = useState<{
    data: T | null;
    error: string | null;
    loading: boolean;
  }>({ data: null, error: null, loading: true });
  useEffect(() => {
    if (!url) return;
    let alive = true;
    const load = () =>
      fetch(url, { credentials: 'same-origin' })
        .then(async (r) => {
          if (!r.ok)
            throw new Error(
              (await r.json().catch(() => ({}))).error ?? r.statusText,
            );
          return r.json();
        })
        .then(
          (data) => alive && setState({ data, error: null, loading: false }),
        )
        .catch(
          (e) =>
            alive &&
            setState((s) => ({
              data: s.data,
              error: String(e.message ?? e),
              loading: false,
            })),
        );
    setState((s) => ({ ...s, loading: true }));
    load();
    const timer = refreshMs ? setInterval(load, refreshMs) : undefined;
    return () => {
      alive = false;
      if (timer) clearInterval(timer);
    };
  }, [url, refreshMs]);
  return state;
}

export function Card({
  title,
  sub,
  children,
  actions,
}: {
  title: ReactNode;
  sub?: ReactNode;
  children: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <section className="card">
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <h2>{title}</h2>
          {sub && <div className="sub">{sub}</div>}
        </div>
        {actions}
      </div>
      {children}
    </section>
  );
}

export function Tile({
  label,
  value,
  note,
}: {
  label: string;
  value: ReactNode;
  note?: ReactNode;
}) {
  return (
    <div className="card tile">
      <div className="label">{label}</div>
      <div className="value">{value}</div>
      {note && <div className="note">{note}</div>}
    </div>
  );
}

export function Seg<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { id: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="seg">
      {options.map((o) => (
        <button
          type="button"
          key={o.id}
          className={o.id === value ? 'on' : ''}
          onClick={() => onChange(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Loading({ error }: { error?: string | null }) {
  return (
    <div className="empty">
      {error ? `Couldn't load: ${error}` : 'Loading…'}
    </div>
  );
}

export const when = (d: string | Date | null | undefined) =>
  d
    ? new Date(d).toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '–';

/** Navigates to a page with query params (hash routing). */
export function go(
  page: string,
  params: Record<string, string | number | undefined> = {},
) {
  const qs = new URLSearchParams(
    Object.entries(params).filter(([, v]) => v !== undefined && v !== '') as [
      string,
      string,
    ][],
  ).toString();
  location.hash = `#/${page}${qs ? `?${qs}` : ''}`;
}

const INCLUDE_TESTS_KEY = 'admin-viewer.include-tests';

/** Whether unit-test worlds' rounds are shown, remembered in this browser. Off by default. */
export function useIncludeTests(): [boolean, (on: boolean) => void] {
  const [on, setOn] = useState(() => {
    try {
      return localStorage.getItem(INCLUDE_TESTS_KEY) === '1';
    } catch {
      return false;
    }
  });
  const set = (value: boolean) => {
    setOn(value);
    try {
      localStorage.setItem(INCLUDE_TESTS_KEY, value ? '1' : '0');
    } catch {
      // Storage blocked: the choice lasts for this page only.
    }
  };
  return [on, set];
}

/** The query parameter that asks the API for test rounds too. */
export const testsParam = (on: boolean) => (on ? '&include_tests=1' : '');

export function TestRoundsToggle({
  value,
  onChange,
}: {
  value: boolean;
  onChange: (on: boolean) => void;
}) {
  return (
    <label className="toggle" title="Rounds from unit-test worlds">
      <input
        type="checkbox"
        checked={value}
        onChange={(e) => onChange(e.target.checked)}
      />{' '}
      Test rounds
    </label>
  );
}
