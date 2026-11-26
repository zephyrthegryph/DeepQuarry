import { describe, expect, it } from 'bun:test';
import { type Ledger, ledgerRows } from './mcHealthData';

const category = (key: string, ema: number, avg = ema) => ({
  key,
  label: key,
  ema_ms: ema,
  avg_ms: avg,
  total_ms: avg * 100,
  count: 10,
  top: [] as [string, number, number, number][],
});

const ledger = (): Ledger => ({
  ticks: 100,
  world_ticks: 100,
  budget_ms: 50,
  window_ema_ms: 12,
  window_avg_ms: 12,
  categories: [
    category('unattributed', 0.4),
    category('timers', 6),
    category('movement', 3.5),
    category('native', 2.1),
    category('garbage', 0),
  ],
  outside: {
    post_ema_ms: 1.5,
    post_avg_ms: 1.5,
    idle_ema_ms: 0,
    idle_avg_ms: 0,
    map_ema_ms: 2,
    map_avg_ms: 2,
  },
  phases: [{ phase: 'K', avg_ms: 0.3, last_ms: 0.3 }],
});

describe('the tick ledger rows', () => {
  it('lists the biggest first and marks the residual as the unknown part', () => {
    const rows = ledgerRows(ledger());
    expect(rows[0].key).toBe('timers');
    expect(rows.find((row) => row.unknown)?.key).toBe('unattributed');
    expect(rows.filter((row) => row.unknown)).toHaveLength(1);
  });

  it('drops categories that never ran and keeps the BYOND time outside the iteration', () => {
    const rows = ledgerRows(ledger());
    expect(rows.find((row) => row.key === 'garbage')).toBeUndefined();
    expect(rows.find((row) => row.key === 'after_kernel')?.ms).toBe(1.5);
    expect(rows.find((row) => row.key === 'map_send')?.ms).toBe(2);
    expect(rows.find((row) => row.key === 'no_kernel')).toBeUndefined();
  });

  it('keeps the categories adding up to the iteration', () => {
    const data = ledger();
    const inside = ledgerRows(data)
      .filter((row) => data.categories.some((c) => c.key === row.key))
      .reduce((sum, row) => sum + row.ms, 0);
    expect(inside).toBeCloseTo(12, 5);
  });
});
