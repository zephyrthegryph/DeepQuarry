import { describe, expect, it } from 'bun:test';
import {
  bytes,
  framePhases,
  histogramPercentile,
  nativeMemoryByArea,
  nativeWork,
  overrunSummary,
  perMinute,
  systemsByCost,
  verdictOf,
  averageTickParts,
  overrunParts,
  tickParts,
} from './mcHealthData';

const win = (avg: number, p99: number, overruns = 0) => ({
  samples: 200,
  avg,
  p50: avg,
  p95: p99,
  p99,
  max: p99,
  overruns,
  tps: 40,
});

describe('what used the tick', () => {
  it('ranks an overrun by its whole breakdown, unattributed time included', () => {
    const parts = overrunParts(
      {
        world_time: 1,
        usage: 200,
        overrun: 100,
        maptick: 10,
        top_systems: [{ key: 'air', ms: 2 }],
        breakdown: [
          { name: 'engine', usage: 20 },
          { name: 'Outside MC', usage: 150 },
          { name: 'MC other', usage: 30 },
        ],
      },
      25,
    );
    expect(parts[0].name).toContain('Before the kernel');
    expect(parts[0].ms).toBeCloseTo(37.5);
    expect(parts.map((p) => p.name)).toContain('air');
    expect(
      parts.find((p) => p.name.startsWith('Not attributed'))?.unknown,
    ).toBe(true);
  });

  it('shows the time the top systems of a recent tick do not explain', () => {
    const parts = tickParts([100, ['air'], [5]], 25);
    expect(parts[0]).toEqual({
      name: 'Everything else',
      ms: 20,
      unknown: true,
    });
  });

  it('adds the unattributed time to the average tick', () => {
    const parts = averageTickParts([{ key: 'air', ms_per_s: 100 }], 50, 25, 40);
    expect(parts.map((p) => p.name)).toEqual(['Not attributed', 'air']);
  });
});

describe('MC Health logic', () => {
  it('says how the server is doing', () => {
    expect(
      verdictOf({ window_5s: win(15, 40), window_5m: win(15, 40) }).label,
    ).toBe('Healthy');
    expect(
      verdictOf({ window_5s: win(30, 60), window_5m: win(30, 60, 3) }).label,
    ).toBe('Strained');
    expect(
      verdictOf({ window_5s: win(95, 180), window_5m: win(95, 180, 80) }).label,
    ).toBe('Overloaded');
  });

  it('reads the slow 1% from histogram buckets', () => {
    const h = {
      count: 100,
      sum: 0,
      max: 9000,
      bounds: [100, 1000, 5000],
      buckets: [90, 8, 1, 1],
    };
    expect(histogramPercentile(h, 0.5)).toBe(100);
    expect(histogramPercentile(h, 0.99)).toBe(5000);
    expect(histogramPercentile(h, 1)).toBe(9000);
    expect(histogramPercentile(null, 0.99)).toBeNull();
  });

  it('formats and rates', () => {
    expect(bytes(2 * 1024 * 1024 * 1024)).toBe('2.0 GB');
    expect(bytes(512)).toBe('512 B');
    expect(perMinute(160, 100, 1200, 600)).toBe(60);
    expect(perMinute(160, undefined, 1200, undefined)).toBeNull();
  });

  it('orders systems and names the overrun leader', () => {
    const sorted = systemsByCost([
      { key: 'a', ms_per_s: 1, p95_ms: 0, overrun_share: 0 },
      { key: 'b', ms_per_s: 5, p95_ms: 0, overrun_share: 0 },
    ]);
    expect(sorted[0].key).toBe('b');
    const line = overrunSummary(
      [
        {
          world_time: 10,
          usage: 130,
          overrun: 30,
          top_systems: [{ key: 'life', ms: 9 }],
        },
        {
          world_time: 20,
          usage: 120,
          overrun: 20,
          top_systems: [{ key: 'life', ms: 7 }],
        },
      ],
      win(50, 120, 4),
    );
    expect(line).toContain('life leads 2 of the last 2 overruns');
  });

  it('reads the native families', () => {
    const rust = {
      'frame.count': 10,
      'frame.us.pace_step': 1000,
      'alloc.gas.current_bytes': 2048,
      'alloc.heap.current_bytes': 9999,
      'world.awake.field_gas_chunks': 4,
      'world.stepped.field_gas_edges': 7,
    };
    expect(framePhases(rust)).toEqual([['Simulate', 100]]);
    expect(nativeMemoryByArea(rust)).toEqual([['gas', 2048]]);
    expect(nativeWork(rust)).toEqual([['gas', 4, 7]]);
  });
});
