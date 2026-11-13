// The tick graph is the first card of the MC Health panel and shows from the first send, before any slow group is built.
import { describe, expect, it } from 'bun:test';
import { cleanup, render } from '@testing-library/react';
import { McHealthPanel } from './McHealth';
import type { McHealthData } from './mcHealthData';

const win = {
  samples: 200,
  avg: 20,
  p50: 20,
  p95: 30,
  p99: 40,
  max: 50,
  overruns: 0,
  tps: 39.5,
};

// The sections the server builds on every send (mc_health_fast()): nothing of the slow groups yet.
const fastOnly = {
  header: {
    tick_budget_ms: 25,
    target_tps: 40,
    current_usage: 20,
    maptick: 1,
    tidi: 0,
  },
  window_5s: win,
  ticks: Array.from({ length: 120 }, (_, i) => [
    15 + (i % 40),
    ['sched_core'],
    [2],
    1,
    1,
  ]),
  stalls: [],
};

const ledger = {
  ticks: 100,
  world_ticks: 100,
  budget_ms: 25,
  window_ema_ms: 20,
  window_avg_ms: 20,
  categories: [],
  outside: {
    post_ema_ms: 0,
    post_avg_ms: 0,
    idle_ema_ms: 0,
    idle_avg_ms: 0,
    map_ema_ms: 0,
    map_avg_ms: 0,
  },
  phases: [],
};

function cardTitles(data: object): (string | null)[] {
  const { container } = render(
    <McHealthPanel data={data as unknown as McHealthData} token={null} />,
  );
  return Array.from(container.querySelectorAll('.mch-card__head h3')).map(
    (h) => h.textContent,
  );
}

describe('MC Health panel order', () => {
  it('draws the recent ticks graph first from the first send, with no slow card yet', () => {
    const titles = cardTitles(fastOnly);
    cleanup();
    expect(titles[0]).toBe('Recent ticks');
    // A slice whose slow group is not built yet is not drawn.
    expect(titles).not.toContain('Where the tick goes');
  });

  it('keeps the recent ticks graph above the other cards once they are built', () => {
    const titles = cardTitles({ ...fastOnly, tick_budget_ms: 25, ledger });
    cleanup();
    expect(titles[0]).toBe('Recent ticks');
    expect(titles.indexOf('Where the tick goes')).toBeGreaterThan(0);
  });
});
