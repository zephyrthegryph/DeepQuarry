// Round rollups and retention. The game only writes raw samples; once a round is over
// (an "end"/"shutdown" round event, or no samples for staleRoundMinutes) its per-metric
// distribution goes into metric_round, which is kept forever. Raw samples older than
// retentionDays are then deleted. Runs on the viewer's timer, or once with `bun run maintain`.

import { config } from './config';
import { db, query } from './db';
import { type Summary, summarize } from './stats';

/** Per-metric summaries of a round computed from its raw samples (for live or unrolled rounds). */
export async function summarizeRound(
  roundId: number,
): Promise<Map<number, Summary>> {
  const rows =
    await db`SELECT key_id, value FROM metric_sample WHERE round_id = ${roundId} ORDER BY key_id`;
  const byKey = new Map<number, number[]>();
  for (const row of rows as { key_id: number; value: number }[]) {
    const values = byKey.get(row.key_id) ?? [];
    if (!byKey.has(row.key_id)) byKey.set(row.key_id, values);
    values.push(row.value);
  }
  const out = new Map<number, Summary>();
  for (const [key, values] of byKey) out.set(key, summarize(values));
  return out;
}

/** Rounds that have samples, no rollup yet, and are over. */
async function finishedUnrolledRounds(): Promise<number[]> {
  const rows = await query<{ round_id: number }>(
    `SELECT s.round_id FROM metric_sample s
		 WHERE NOT EXISTS (SELECT 1 FROM metric_round r WHERE r.round_id = s.round_id)
		 GROUP BY s.round_id
		 HAVING MAX(s.ts) < NOW() - INTERVAL ? MINUTE
		    OR EXISTS (SELECT 1 FROM metric_event e WHERE e.round_id = s.round_id AND e.kind = 'round' AND e.category IN ('end', 'shutdown'))`,
    [config.staleRoundMinutes],
  );
  return rows.map((r) => r.round_id);
}

export async function rollupRound(roundId: number): Promise<number> {
  const summaries = await summarizeRound(roundId);
  for (const [keyId, s] of summaries) {
    await db`INSERT INTO metric_round (round_id, key_id, n, mean, min, p50, p95, p99, max)
			VALUES (${roundId}, ${keyId}, ${s.n}, ${s.mean}, ${s.min}, ${s.p50}, ${s.p95}, ${s.p99}, ${s.max})
			ON DUPLICATE KEY UPDATE n = VALUES(n), mean = VALUES(mean), min = VALUES(min), p50 = VALUES(p50),
				p95 = VALUES(p95), p99 = VALUES(p99), max = VALUES(max)`;
  }
  return summaries.size;
}

/** Deletes raw samples past retention, in batches, from rounds that are already rolled up. */
export async function pruneSamples(): Promise<number> {
  let total = 0;
  for (;;) {
    const result = (await query(
      `DELETE FROM metric_sample WHERE ts < NOW() - INTERVAL ? DAY
			 AND round_id IN (SELECT round_id FROM (SELECT DISTINCT round_id FROM metric_round) rolled) LIMIT 20000`,
      [config.retentionDays],
    )) as unknown as { affectedRows?: number };
    const deleted = result.affectedRows ?? 0;
    total += deleted;
    if (deleted < 20000) return total;
  }
}

export async function runMaintenance(log = console.log): Promise<void> {
  for (const roundId of await finishedUnrolledRounds()) {
    const keys = await rollupRound(roundId);
    log(`maintenance: rolled up round ${roundId} (${keys} metrics)`);
  }
  const pruned = await pruneSamples();
  if (pruned)
    log(
      `maintenance: pruned ${pruned} samples older than ${config.retentionDays} days`,
    );
}

if (import.meta.main) {
  await runMaintenance();
  await db.close();
}
