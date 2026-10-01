// Viewer settings, all from the environment (see ../README.md).

export const config = {
  /** MariaDB/MySQL URL of the game database (the same one config/dbconfig.txt points at). */
  databaseUrl:
    process.env.DATABASE_URL ?? 'mysql://root@127.0.0.1:3306/feedback',
  /** Shared with the game's METRICS_VIEWER_SECRET; signs and verifies staff links. */
  secret: process.env.VIEWER_SECRET ?? '',
  host: process.env.VIEWER_HOST ?? '127.0.0.1',
  port: Number(process.env.VIEWER_PORT ?? 8090),
  /** Raw samples older than this are deleted (rounds keep their metric_round summary). */
  retentionDays: Number(process.env.METRICS_RETENTION_DAYS ?? 30),
  /** Previous rounds a round is compared against for outliers. */
  baselineRounds: Number(process.env.BASELINE_ROUNDS ?? 20),
  /** A round with no samples for this long (and no end event) is treated as finished. */
  staleRoundMinutes: Number(process.env.STALE_ROUND_MINUTES ?? 15),
  /** Where runtime locations link to (…/blob/<commit>/<file>#L<line>). */
  repoUrl:
    process.env.REPO_URL ?? 'https://github.com/zephyrthegryph/DeepQuarry',
  /** Repository root, for ingesting data/test-runs and data/bench/runs. */
  repoRoot:
    process.env.REPO_ROOT ?? new URL('../../..', import.meta.url).pathname,
};
