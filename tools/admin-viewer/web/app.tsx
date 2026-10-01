import { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { BenchPage, TestsPage } from './pages/dev';
import { OverrunsPage, RuntimesPage, StaffPage } from './pages/events';
import { OverviewPage, PerformancePage, RoundsPage } from './pages/perf';
import { useApi } from './util';

type Me = { ckey: string; admin: boolean; expires: number };

const PAGES: { id: string; label: string; admin?: boolean }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'performance', label: 'Performance' },
  { id: 'rounds', label: 'Rounds' },
  { id: 'runtimes', label: 'Runtimes' },
  { id: 'overruns', label: 'Tick overruns' },
  { id: 'staff', label: 'Staff & tickets', admin: true },
  { id: 'tests', label: 'Unit tests' },
  { id: 'bench', label: 'Benchmarks' },
];

/** "#/page?a=1" -> ["page", URLSearchParams]. */
function readHash(): [string, URLSearchParams] {
  const raw = location.hash.replace(/^#\/?/, '');
  const [page, qs] = raw.split('?');
  return [page || 'overview', new URLSearchParams(qs ?? '')];
}

function App() {
  const [[page, params], setRoute] = useState(readHash());
  useEffect(() => {
    const on = () => setRoute(readHash());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  const me = useApi<Me>('/api/me');
  const [menuOpen, setMenuOpen] = useState(false);
  const [theme, setTheme] = useState<string | null>(() => {
    try {
      return localStorage.getItem('dq-viewer-theme');
    } catch {
      return null;
    }
  });
  useEffect(() => {
    if (theme) document.documentElement.dataset.theme = theme;
    else delete document.documentElement.dataset.theme;
    try {
      if (theme) localStorage.setItem('dq-viewer-theme', theme);
    } catch {}
  }, [theme]);

  if (me.error) {
    return (
      <main>
        <h1>DeepQuarry Admin Viewer</h1>
        <p className="muted">
          Not signed in, or your link expired. Open the viewer from the game
          with the <b>Admin Viewer</b> verb (Debug › Investigate).
        </p>
      </main>
    );
  }
  const props = { params };
  const current = PAGES.find((p) => p.id === page)?.label ?? '';
  return (
    <div className="app">
      <nav className={`nav${menuOpen ? ' open' : ''}`}>
        <div className="brand">
          DeepQuarry
          <small>Admin viewer</small>
        </div>
        <span className="nav-current">{current}</span>
        <button
          type="button"
          className="nav-toggle"
          aria-expanded={menuOpen}
          aria-label="Menu"
          onClick={() => setMenuOpen(!menuOpen)}
        >
          {menuOpen ? 'Close' : 'Menu'}
        </button>
        {PAGES.filter((p) => !p.admin || me.data?.admin).map((p) => (
          <a
            key={p.id}
            href={`#/${p.id}`}
            className={page === p.id ? 'active' : ''}
            onClick={() => setMenuOpen(false)}
          >
            {p.label}
          </a>
        ))}
        <div className="spacer" />
        {me.data && <div className="who">Signed in as {me.data.ckey}</div>}
        <button
          type="button"
          className="theme-toggle"
          onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')}
        >
          {theme === 'light' ? 'Dark theme' : 'Light theme'}
        </button>
      </nav>
      <main>
        {page === 'overview' && <OverviewPage {...props} />}
        {page === 'performance' && <PerformancePage {...props} />}
        {page === 'rounds' && <RoundsPage {...props} />}
        {page === 'runtimes' && <RuntimesPage {...props} />}
        {page === 'overruns' && <OverrunsPage {...props} />}
        {page === 'staff' && <StaffPage {...props} />}
        {page === 'tests' && <TestsPage {...props} />}
        {page === 'bench' && <BenchPage {...props} />}
      </main>
    </div>
  );
}

createRoot(document.getElementById('root') as HTMLElement).render(<App />);
