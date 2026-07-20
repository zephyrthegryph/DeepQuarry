import '../__mocks__/setup';
import { afterEach, describe, expect, test } from 'bun:test';
import { act, cleanup, render } from '@testing-library/react';
import { Profiler, type ProfilerOnRenderCallback } from 'react';
import { PowerMonitorFocus } from '../interfaces/PowerMonitor/PowerMonitorFocus';
import type { areaPayload } from '../interfaces/PowerMonitor/types';
import { percentile } from './metrics';

const AREA_COUNT = 600;
const UPDATES = 12;

afterEach(cleanup);

function makeAreas(): areaPayload[] {
  return Array.from({ length: AREA_COUNT }, (_, index) => [
    `Station Area ${index}`,
    50 + (index % 50),
    `${index % 9000} W`,
    index % 3,
    index % 4,
    (index + 1) % 4,
    (index + 2) % 4,
  ]);
}

describe('Power Monitor performance', () => {
  test('compact area tuples substantially reduce recurring payload size', () => {
    const tuples = makeAreas();
    const objects = tuples.map(
      ([name, charge, load, charging, eqp, lgt, env]) => ({
        name,
        charge,
        load,
        charging,
        eqp,
        lgt,
        env,
      }),
    );
    const tupleBytes = JSON.stringify(tuples).length;
    const objectBytes = JSON.stringify(objects).length;
    console.info(
      `[power monitor benchmark] ${AREA_COUNT} areas: ${objectBytes}B objects → ${tupleBytes}B tuples`,
    );
    expect(tupleBytes).toBeLessThan(objectBytes * 0.55);
  });

  test('unchanged large grids avoid expensive repeat commits', () => {
    const commits: number[] = [];
    const onRender: ProfilerOnRenderCallback = (_id, _phase, duration) =>
      commits.push(duration);
    const focus = {
      name: 'Station Grid',
      stored: 60,
      interval: 1,
      attached: 1,
      history: { supply: [500_000], demand: [250_000] },
      areas: makeAreas(),
    };
    const view = render(
      <Profiler id="power-monitor" onRender={onRender}>
        <PowerMonitorFocus focus={focus} />
      </Profiler>,
    );
    for (let index = 0; index < UPDATES; index++) {
      act(() =>
        view.rerender(
          <Profiler id="power-monitor" onRender={onRender}>
            <PowerMonitorFocus focus={{ ...focus, areas: makeAreas() }} />
          </Profiler>,
        ),
      );
    }
    const p95 = percentile(commits.slice(1), 0.95);
    console.info(
      `[power monitor benchmark] ${AREA_COUNT} areas, ${UPDATES} unchanged updates: ${p95.toFixed(2)}ms p95`,
    );
    expect(p95).toBeLessThan(35);
  });
});
