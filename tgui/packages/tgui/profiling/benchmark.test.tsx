import { afterEach, describe, expect, test } from 'bun:test';
import { act, cleanup, render } from '@testing-library/react';
import { Profiler, type ProfilerOnRenderCallback } from 'react';
import { Button } from 'tgui-core/components';
import { percentile } from './metrics';

const BUTTONS = 240;
const UPDATES = 40;
const COMMIT_P95_BUDGET_MS = 35;
const TOTAL_BUDGET_MS = 1500;

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

describe('TGUI render benchmark', () => {
  test('large button interface remains within the development render budget', () => {
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
    const p95 = percentile(commits.slice(1), 0.95);
    console.info(
      `[tgui benchmark] ${BUTTONS} buttons, ${UPDATES} updates: ` +
        `${total.toFixed(1)}ms total, ${p95.toFixed(2)}ms commit p95`,
    );
    expect(commits.length).toBe(UPDATES + 1);
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
