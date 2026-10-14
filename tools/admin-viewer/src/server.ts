// The admin viewer: a Bun HTTP server serving the React app (web/) and the JSON API (api.ts),
// behind staff links signed by the game (auth.ts). Run with `bun run start`; see ../README.md.

import index from '../web/index.html';
import * as api from './api';
import { R_ADMIN, type Session, verifyToken } from './auth';
import { config } from './config';
import { runMaintenance } from './maintenance';

if (!config.secret) {
  console.error(
    "VIEWER_SECRET is not set: it must match the game's METRICS_VIEWER_SECRET.",
  );
  process.exit(1);
}

const COOKIE = 'dq_viewer';

function session(req: Request): Session | null {
  const cookie = req.headers.get('cookie') ?? '';
  const match = cookie.split(/;\s*/).find((c) => c.startsWith(`${COOKIE}=`));
  return match
    ? verifyToken(
        decodeURIComponent(match.slice(COOKIE.length + 1)),
        config.secret,
      )
    : null;
}

const json = (data: unknown, status = 200) =>
  new Response(
    JSON.stringify(data, (_k, v) => (typeof v === 'bigint' ? Number(v) : v)),
    {
      status,
      headers: {
        'content-type': 'application/json',
        'cache-control': 'no-store',
      },
    },
  );

type Handler = (q: URLSearchParams, s: Session) => Promise<unknown>;
/** API routes; `admin` routes need R_ADMIN on top of viewer rights. */
const routes: Record<string, { handler: Handler; admin?: boolean }> = {
  '/api/me': {
    handler: async (_q, s) => ({
      ckey: s.ckey,
      rights: s.rights,
      expires: s.expires,
      admin: !!(s.rights & R_ADMIN),
    }),
  },
  '/api/rounds': { handler: api.rounds },
  '/api/series': { handler: api.series },
  '/api/breakdown': { handler: api.breakdown },
  '/api/outliers': { handler: api.outliers },
  '/api/stalls': { handler: api.stalls },
  '/api/trend': { handler: api.trend },
  '/api/categories': { handler: api.categories },
  '/api/runtimes': { handler: api.runtimes },
  '/api/overruns': { handler: api.overruns },
  '/api/staff': { handler: api.staff, admin: true },
  '/api/tests': { handler: api.tests },
  '/api/tests/history': { handler: api.testHistory },
  '/api/bench': { handler: api.bench },
};

const server = Bun.serve({
  hostname: config.host,
  port: config.port,
  routes: {
    '/': index,
    // The game opens /auth?token=...&next=/page: the token becomes a session cookie that
    // lasts as long as the token does.
    '/auth': (req) => {
      const url = new URL(req.url);
      const token = url.searchParams.get('token');
      const s = verifyToken(token, config.secret);
      if (!s || !token)
        return new Response(
          'This viewer link is invalid or has expired. Open a new one from the game (Admin Viewer verb).',
          { status: 403 },
        );
      const next = url.searchParams.get('next') ?? '/';
      const target =
        next.startsWith('/') && !next.startsWith('//') ? next : '/';
      const maxAge = Math.max(Math.floor(s.expires - Date.now() / 1000), 0);
      return new Response(null, {
        status: 302,
        headers: {
          location: target === '/' ? '/' : `/#${target}`,
          'set-cookie': `${COOKIE}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}`,
        },
      });
    },
    '/logout': () =>
      new Response(null, {
        status: 302,
        headers: {
          location: '/',
          'set-cookie': `${COOKIE}=; Path=/; Max-Age=0`,
        },
      }),
  },
  async fetch(req) {
    const url = new URL(req.url);
    const route = routes[url.pathname];
    if (!route) return json({ error: 'not found' }, 404);
    const s = session(req);
    if (!s) return json({ error: 'not signed in' }, 401);
    if (route.admin && !(s.rights & R_ADMIN))
      return json({ error: 'needs +ADMIN' }, 403);
    try {
      return json(await route.handler(url.searchParams, s));
    } catch (err) {
      console.error(`${url.pathname}: ${(err as Error).stack ?? err}`);
      return json({ error: 'query failed' }, 500);
    }
  },
  development: process.env.NODE_ENV !== 'production' && {
    hmr: false,
    console: false,
  },
});

console.log(`admin viewer on http://${server.hostname}:${server.port}`);

// Roll finished rounds up and prune old samples now and every ten minutes.
const maintain = () =>
  runMaintenance().catch((err) => console.error(`maintenance failed: ${err}`));
maintain();
setInterval(maintain, 10 * 60_000);
