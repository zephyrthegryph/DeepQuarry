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

describe('MC Health panel order', () => {
  it('puts the recent ticks graph above every other card, from the first send', () => {
    const { container } = render(
      <McHealthPanel data={fastOnly as unknown as McHealthData} token={null} />,
    );
    const titles = Array.from(
      container.querySelectorAll('.mch-card__head h3'),
    ).map((h) => h.textContent);
    expect(titles[0]).toBe('Recent ticks');
    expect(titles.indexOf('Where the tick goes')).toBeGreaterThan(0);
    cleanup();
  });
});
