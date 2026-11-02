import { afterEach, describe, expect, test } from 'bun:test';
import { act, cleanup, render } from '@testing-library/react';
import { Profiler, type ProfilerOnRenderCallback } from 'react';
import { Button } from 'tgui-core/components';
import { percentile } from './metrics';

const BUTTONS = 240;
const UPDATES = 40;
const COMMIT_P95_BUDGET_MS = 35;
const TOTAL_BUDGET_MS = 1500;
/**
 * The run is timed this many times and the fastest trial is judged. A trial is wall-clock time on a desktop that also runs builds, test
 * worlds and games: a load spike only ever makes a trial slower, so the fastest trial is the closest to what the code costs, and one slow
 * trial cannot fail the test. The budgets are unchanged.
 */
const TRIALS = 3;

afterEach(cleanup);

function ButtonGrid({ selected }: { selected: number }) {
  return (
    <div>
      {Array.from({ length: BUTTONS }, (_, index) => (
        <Button key={index} icon="cog" selected={selected === index}>
          Benchmark {index}
        </Button>
      ))}
    </div>
  );
}

/** One timed trial: mount the grid, then move the selection UPDATES times. */
function trial(): { total: number; p95: number; commits: number } {
  const commits: number[] = [];
  const onRender: ProfilerOnRenderCallback = (_id, _phase, duration) =>
    commits.push(duration);
  const started = performance.now();
  const view = render(
    <Profiler id="button-grid" onRender={onRender}>
      <ButtonGrid selected={0} />
    </Profiler>,
  );
  for (let selected = 1; selected <= UPDATES; selected++) {
    act(() =>
      view.rerender(
        <Profiler id="button-grid" onRender={onRender}>
          <ButtonGrid selected={selected} />
        </Profiler>,
      ),
    );
  }
  const total = performance.now() - started;
  view.unmount();
  return {
    total,
    p95: percentile(commits.slice(1), 0.95),
    commits: commits.length,
  };
}

describe('TGUI render benchmark', () => {
  test('large button interface remains within the development render budget', () => {
    const trials = Array.from({ length: TRIALS }, trial);
    const total = Math.min(...trials.map((t) => t.total));
    const p95 = Math.min(...trials.map((t) => t.p95));
    console.info(
      `[tgui benchmark] ${BUTTONS} buttons, ${UPDATES} updates: ` +
        `${total.toFixed(1)}ms total, ${p95.toFixed(2)}ms commit p95 (fastest of ${TRIALS}: ` +
        `${trials.map((t) => t.total.toFixed(0)).join('/')}ms)`,
    );
    for (const t of trials) expect(t.commits).toBe(UPDATES + 1);
    expect(p95).toBeLessThan(COMMIT_P95_BUDGET_MS);
    expect(total).toBeLessThan(TOTAL_BUDGET_MS);
  });

  test('button descendants retain a pointer cursor across rerenders', () => {
    const style = document.createElement('style');
    style.textContent =
      '.Button,.Button *{cursor:pointer}.Button--disabled,.Button--disabled *{cursor:default}';
    document.head.append(style);
    const view = render(<Button icon="cog">Hover target</Button>);
    const button = view.container.querySelector('.Button')!;
    const content = view.container.querySelector('.Button__content')!;
    const icon = view.container.querySelector('.Button--icon')!;
    expect(getComputedStyle(button).cursor).toBe('pointer');
    expect(getComputedStyle(content).cursor).toBe('pointer');
    expect(getComputedStyle(icon).cursor).toBe('pointer');
    for (let index = 0; index < 25; index++) {
      view.rerender(
        <Button icon="cog" selected={index % 2 === 0}>
          Hover target
        </Button>,
      );
      expect(view.container.querySelector('.Button')).toBe(button);
      expect(getComputedStyle(content).cursor).toBe('pointer');
      expect(getComputedStyle(icon).cursor).toBe('pointer');
    }
    style.remove();
  });
});
