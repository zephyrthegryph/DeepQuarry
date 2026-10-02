# Admin viewer

A small web app for staff: server performance over time (broken down by MC subsystem, world
service, OM lane and behaviour, with outliers flagged against recent rounds), runtimes, tick
overruns, tickets and admin activity, and unit-test and benchmark history. It reads the game
database; it adds no services beyond the MariaDB the server already uses, and needs only Bun
(already used by the build).

```
game (code/modules/metrics/)  --om_io batched writes-->  MariaDB metric_* tables
tools/admin-viewer/ingest.ts  --data/test-runs, data/bench/runs-->  test_* / bench_* tables
tools/admin-viewer/server.ts  <--reads--  MariaDB;  rolls rounds up, prunes old samples
staff  --Admin Viewer verb (signed link)-->  viewer (in a game window or their browser)
```

## Setup

1. Create the tables: `mysql feedback < SQL/metrics_schema.sql` (docker-compose loads it
   automatically on a fresh database).
2. In `config/dbconfig.txt` (see `config/example/dbconfig.txt`):
   ```
   METRICS_ENABLED
   METRICS_VIEWER_URL http://127.0.0.1:8090
   METRICS_VIEWER_SECRET <a long random string>
   ```
   Put the viewer behind your reverse proxy and use that public URL if staff should reach it from
   outside the host.
3. Start the viewer on the same machine:
   ```sh
   cd tools/admin-viewer
   bun install
   VIEWER_SECRET=<the same string> DATABASE_URL=mysql://user:pass@127.0.0.1:3306/feedback bun run start
   ```
4. In game, staff with +ADMIN, +SERVER or +DEBUG use **Admin Viewer** (game window) or
   **Admin Viewer (Browser)** under Debug › Investigate. The staff and tickets page needs +ADMIN.

From the host, `bun run mint <ckey> [hours]` prints a sign-in link without the game.

## Environment

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | `mysql://root@127.0.0.1:3306/feedback` | The game database. |
| `VIEWER_SECRET` | (required) | Same value as the game's `METRICS_VIEWER_SECRET`. |
| `VIEWER_HOST` / `VIEWER_PORT` | `127.0.0.1` / `8090` | Where the viewer listens. |
| `METRICS_RETENTION_DAYS` | `30` | Raw 10 s samples are deleted after this; per-round summaries are kept forever. |
| `BASELINE_ROUNDS` | `20` | How many previous rounds a round is compared against for outliers. |
| `STALE_ROUND_MINUTES` | `3` | A round with no samples for this long counts as finished (for crashes); a round that ended or shut down is never live. |
| `TEST_MAPS` | `Virgo_minitest` | Comma-separated maps only unit-test worlds load. Their rounds (and rounds flagged `test` at start, or that never started) are hidden unless "Test rounds" is ticked. |
| `TICK_MS` | `25` | The server's tick length (1000 / FPS), used to read overrun records written before they carried a cause. |
| `REPO_URL` | this repository | Runtime locations link to `REPO_URL/blob/<commit>/<file>#L<line>`. |

## Test and benchmark history

`bun run ingest [repo root]` loads every `data/test-runs/*.json` and `data/bench/runs/*.json` not
loaded yet. Run it after `dm-test`, `test-repeat` or `bench`, or as the last CI step with
`DATABASE_URL` pointing at the database the viewer reads.

## How it works

* **Recording** (`code/modules/metrics/`): `GLOB.metrics_service` samples every
  `/datum/metrics_source` every 10 s and flushes once a minute through `om_io`, so the game never
  waits on the database. Runtimes and overruns are counted in memory and written once per flush
  (grouped by signature, with the proc and a trimmed call stack; the worst overrun ticks keep their full
  breakdown and a cause: a subsystem, an object-model system, or "Outside MC" when time before or after the
  MC's own run dominates, with the slowest single entity step when one took over a tick). The tick is
  also split at the MC every tick from `/world/Tick` (`frame/*` metrics), and the server profiles the
  first minute of each round and a few seconds after any tick over 300% (`profile` events, on the
  Overruns page). Events (`METRICS_EVENT`)
  come from single framework points: the admin verb dispatcher, the ticket list, the ticker, world/Error
  and the MC tick record. To measure something new, add a `/datum/metrics_source` subtype.
* **Rollups and retention** (`src/maintenance.ts`): when a round ends, its per-metric distribution
  (mean, min, p50, p95, p99, max) goes into `metric_round`; raw samples past retention are pruned.
  This runs in the viewer every ten minutes, so it costs the game nothing and still happens after a crash.
* **Outliers**: a metric is flagged when its p95 (or the chosen statistic) is at least 1.5× its median
  over the previous `BASELINE_ROUNDS` rounds, by a margin that matters for its unit, with at least
  three rounds of history.
* **Sign-in**: links are `ckey|rights|expiry|signature`, signed with
  `sha256(secret + sha256(secret + payload))` (rust-g has no HMAC; the outer hash prevents length
  extension). The viewer turns a valid link into an HttpOnly cookie that expires with it.
