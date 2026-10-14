// Loads unit-test runs (data/test-runs/*.json) and benchmark runs (data/bench/runs/*.json) into
// the test_* / bench_* tables. Idempotent: a run already loaded is skipped. Run it after a test
// or bench run, or at the end of CI: `bun run ingest [repo root]`.

import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { config } from './config';
import { db } from './db';

/** A run with fewer tests than this is a focused run (the full suite is ~2000). */
const FOCUSED_BELOW = 1000;

const root = process.argv[2] ?? config.repoRoot;

async function jsonFiles(dir: string): Promise<string[]> {
  try {
    return (await readdir(dir))
      .filter((f) => f.endsWith('.json'))
      .map((f) => join(dir, f));
  } catch {
    return [];
  }
}

const sqlTime = (iso: string) =>
  new Date(iso).toISOString().slice(0, 19).replace('T', ' ');

async function ingestTestRun(file: string): Promise<boolean> {
  const run = await Bun.file(file).json();
  if (run.kind !== 'test' || !run.id || !run.tests) return false;
  const exists = await db`SELECT 1 FROM test_run WHERE id = ${run.id}`;
  if (exists.length) return false;
  const counts = run.counts ?? {};
  const total =
    (counts.passed ?? 0) + (counts.failed ?? 0) + (counts.skipped ?? 0);
  await db.begin(async (tx) => {
    await tx`INSERT INTO test_run (id, ts, commit_hash, branch, label, host, clean, duration_s, passed, failed, skipped, focused)
			VALUES (${run.id}, ${sqlTime(run.timestamp)}, ${run.commit ?? ''}, ${run.branch ?? ''}, ${run.label ?? ''}, ${run.host ?? ''},
				${run.clean ? 1 : 0}, ${run.duration_seconds ?? 0}, ${counts.passed ?? 0}, ${counts.failed ?? 0}, ${counts.skipped ?? 0}, ${total < FOCUSED_BELOW ? 1 : 0})`;
    const rows = Object.values(
      run.tests as Record<
        string,
        {
          name: string;
          status: number;
          duration_ds: number;
          runtimes: number;
          message: string;
        }
      >,
    ).map((t) => ({
      run_id: run.id,
      test: t.name.slice(0, 160),
      status: t.status,
      duration_s: (t.duration_ds ?? 0) / 10,
      runtimes: t.runtimes ?? 0,
      message: (t.message ?? '').trim().slice(0, 512),
    }));
    for (let i = 0; i < rows.length; i += 500)
      await tx`INSERT INTO test_result ${tx(rows.slice(i, i + 500))}`;
  });
  return true;
}

type SummaryEntry = {
  unit?: string;
  better?: string;
  median?: number;
  mean?: number;
};

async function ingestBenchRun(file: string): Promise<boolean> {
  const run = await Bun.file(file).json();
  if (run.kind !== 'bench' || !run.id) return false;
  const exists = await db`SELECT 1 FROM bench_run WHERE id = ${run.id}`;
  if (exists.length) return false;
  const measured = (run.iterations ?? []).filter(
    (i: { warmup?: boolean }) => !i.warmup,
  );
  const map = measured[0]?.map ?? run.map ?? '';
  const rows: {
    run_id: string;
    name: string;
    category: string;
    value: number;
    unit: string;
    better: string;
  }[] = [];
  for (const [category, entries] of Object.entries(
    (run.summary ?? {}) as Record<string, Record<string, SummaryEntry>>,
  )) {
    for (const [name, s] of Object.entries(entries)) {
      const value = s.median ?? s.mean;
      if (typeof value !== 'number') continue;
      rows.push({
        run_id: run.id,
        name: `${category}/${name}`.slice(0, 128),
        category: category.slice(0, 32),
        value,
        unit: (s.unit ?? '').slice(0, 16),
        better: s.better ?? 'none',
      });
    }
  }
  await db.begin(async (tx) => {
    await tx`INSERT INTO bench_run (id, ts, commit_hash, branch, label, host, map, iterations)
			VALUES (${run.id}, ${sqlTime(run.timestamp)}, ${run.commit ?? ''}, ${run.branch ?? ''}, ${run.label ?? ''}, ${run.host ?? ''}, ${map}, ${measured.length})`;
    for (let i = 0; i < rows.length; i += 500)
      await tx`INSERT INTO bench_metric ${tx(rows.slice(i, i + 500))}`;
  });
  return true;
}

let tests = 0;
let benches = 0;
for (const file of await jsonFiles(join(root, 'data/test-runs')))
  if (await ingestTestRun(file)) tests++;
for (const file of await jsonFiles(join(root, 'data/bench/runs')))
  if (await ingestBenchRun(file)) benches++;
console.log(
  `ingest: ${tests} new test runs, ${benches} new bench runs from ${root}`,
);
await db.close();
