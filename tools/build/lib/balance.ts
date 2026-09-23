/**
 * Storage and comparison for the medical and combat balance harness
 * (code/modules/balance). The world writes data/balance/results.json; the
 * `balance` target stores each run in data/balance/runs/ and `balance-compare`
 * diffs two of them. Balance numbers have no "better" direction, so every
 * change beyond the threshold is reported, and a value that appears or
 * disappears (null = "never happened within the cap") always is.
 */

import fs from 'node:fs';
import { formatNumber, type RunIdentity } from './bench';

export const BALANCE_RESULTS_FILE = 'data/balance/results.json';
export const BALANCE_RUNS_DIR = 'data/balance/runs';

export type BalanceScenario = {
  id: string;
  description?: string;
  status: string;
  error?: string;
  duration_seconds?: number;
  runtimes?: number;
  missing_keys?: string[];
  results: Record<string, number | null>;
  units: Record<string, string>;
  notes: string[];
};

export type BalanceWorldDocument = {
  kind: 'balance';
  byond_version: string;
  map: string | null;
  seed: number;
  life_seconds: number;
  scenarios: Record<string, BalanceScenario>;
};

export type BalanceRun = RunIdentity & {
  kind: 'balance';
  label: string | null;
  world: BalanceWorldDocument;
  failures: string[];
};

export type BalanceChange = {
  key: string;
  base: number | null | undefined;
  head: number | null | undefined;
  unit: string;
  deltaPct: number | null;
};

/** Every result of a run as one flat map. */
export function flattenBalance(world: BalanceWorldDocument): {
  values: Record<string, number | null>;
  units: Record<string, string>;
} {
  const values: Record<string, number | null> = {};
  const units: Record<string, string> = {};
  for (const scenario of Object.values(world.scenarios)) {
    for (const [key, value] of Object.entries(scenario.results ?? {}))
      values[key] = value;
    Object.assign(units, scenario.units ?? {});
  }
  return { values, units };
}

/** Problems a run should fail on: failed scenarios, runtimes, missing keys. */
export function balanceFailures(world: BalanceWorldDocument): string[] {
  const failures: string[] = [];
  for (const scenario of Object.values(world.scenarios)) {
    if (scenario.status !== 'passed')
      failures.push(
        `${scenario.id} ${scenario.status}: ${scenario.error ?? ''}`,
      );
    if (scenario.runtimes)
      failures.push(`${scenario.id}: ${scenario.runtimes} runtime(s)`);
    if (scenario.missing_keys?.length)
      failures.push(
        `${scenario.id}: ${scenario.missing_keys.length} missing key(s), e.g. ${scenario.missing_keys.slice(0, 5).join(', ')}`,
      );
  }
  return failures;
}

/**
 * Keys whose value changed by more than `thresholdPct` percent, or appeared,
 * disappeared or went between a number and null.
 */
export function compareBalance(
  base: BalanceWorldDocument,
  head: BalanceWorldDocument,
  thresholdPct: number,
): BalanceChange[] {
  const a = flattenBalance(base);
  const b = flattenBalance(head);
  const keys = [
    ...new Set([...Object.keys(a.values), ...Object.keys(b.values)]),
  ].sort();
  const changes: BalanceChange[] = [];
  for (const key of keys) {
    const before = key in a.values ? a.values[key] : undefined;
    const after = key in b.values ? b.values[key] : undefined;
    const unit = b.units[key] ?? a.units[key] ?? '';
    if (typeof before === 'number' && typeof after === 'number') {
      if (before === after) continue;
      const deltaPct =
        before === 0 ? null : ((after - before) / Math.abs(before)) * 100;
      if (deltaPct !== null && Math.abs(deltaPct) <= thresholdPct) continue;
      changes.push({ key, base: before, head: after, unit, deltaPct });
    } else if (before !== after) {
      changes.push({ key, base: before, head: after, unit, deltaPct: null });
    }
  }
  return changes;
}

function show(value: number | null | undefined): string {
  if (value === undefined) return 'absent';
  if (value === null) return 'never';
  return formatNumber(value);
}

export function formatBalanceChanges(changes: BalanceChange[]): string {
  if (!changes.length) return 'No balance numbers changed.';
  const width = Math.min(Math.max(...changes.map((c) => c.key.length)), 70);
  return changes
    .map((c) => {
      const delta =
        c.deltaPct === null
          ? ''
          : ` (${c.deltaPct > 0 ? '+' : ''}${c.deltaPct.toFixed(1)}%)`;
      return `  ${c.key.padEnd(width)} ${show(c.base).padStart(10)} -> ${show(c.head).padStart(10)} ${c.unit}${delta}`;
    })
    .join('\n');
}

export function readBalanceResults(
  file = BALANCE_RESULTS_FILE,
): BalanceWorldDocument {
  return JSON.parse(fs.readFileSync(file, 'utf-8')) as BalanceWorldDocument;
}
