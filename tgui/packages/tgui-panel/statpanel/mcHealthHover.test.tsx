// Hovering a tick in the graph must not change the layout: the details area is always there, so the bar under the cursor stays put.
import { describe, expect, it } from 'bun:test';
import { cleanup, fireEvent, render } from '@testing-library/react';
import { McHealthPanel } from './McHealth';
import type { McHealthData } from './mcHealthData';

const data = {
  header: {
    tick_budget_ms: 25,
    target_tps: 40,
    current_usage: 20,
    maptick: 1,
    tidi: 0,
  },
  window_5s: {
    samples: 200,
    avg: 20,
    p50: 20,
    p95: 30,
    p99: 40,
    max: 50,
    overruns: 0,
    tps: 39.5,
  },
  tick_budget_ms: 25,
  ticks: Array.from({ length: 30 }, (_, i) => [
    15 + i,
    ['sched_core', 'ai'],
    [2, 3],
    1,
    1,
  ]),
  stalls: [],
};

function structure(el: Element | null): string {
  if (!el) return '';
  return Array.from(el.children)
    .map((c) => `${c.tagName}.${c.className}`)
    .join('|');
}

describe('MC Health tick graph hover', () => {
  it('keeps the graph and its card layout the same while hovering and pinning', () => {
    const { container } = render(
      <McHealthPanel data={data as unknown as McHealthData} token={null} />,
    );
    const timeline = container.querySelector('.mch-timeline') as HTMLElement;
    const card = timeline.parentElement as HTMLElement;
    const detail = card.querySelector('.mch-tickdetail') as HTMLElement;
    const before = structure(card);
    const bars = timeline.querySelectorAll('.mch-bar');
    expect(bars.length).toBe(30);

    fireEvent.mouseEnter(timeline);
    fireEvent.mouseEnter(bars[5]);
    expect(detail.textContent).toContain('of the tick');
    // Same nodes, same order: nothing was added or removed around the graph.
    expect(structure(card)).toBe(before);
    expect(card.querySelector('.mch-timeline')).toBe(timeline);
    expect(card.querySelector('.mch-tickdetail')).toBe(detail);
    expect(timeline.children.length).toBe(bars.length + 1);

    fireEvent.mouseEnter(bars[6]);
    expect(structure(card)).toBe(before);

    fireEvent.click(bars[6]);
    fireEvent.mouseLeave(timeline);
    expect(detail.textContent).toContain('pinned');
    expect(structure(card)).toBe(before);
    cleanup();
  });
});
