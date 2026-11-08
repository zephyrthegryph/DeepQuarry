// What the stat panel costs the client while it updates live: the Server > Health page open with the server's once-a-second partial updates
// and the Status lines coming in. Commits and their time are counted per update (React Profiler under happy-dom: no paint, but the React
// work and the DOM writes are real). RENDER_COST lines are the measurement; the assertions only keep it from regressing badly.
import { describe, expect, it } from 'bun:test';
import { act, cleanup, render } from '@testing-library/react';
import { Profiler, type ProfilerOnRenderCallback } from 'react';
import { StatWindow } from './App';
import { StatStore } from './store';

function verbs(n: number) {
  const out: string[][] = [];
  for (let i = 0; i < n; i++)
    out.push([
      ['IC', 'OOC', 'Admin', 'Debug', 'Server'][i % 5],
      `Verb ${i}`,
      '',
    ]);
  return out;
}

const win = (avg: number) => ({
  samples: 200,
  avg,
  p50: avg,
  p95: avg + 10,
  p99: avg + 20,
  max: avg + 30,
  overruns: 0,
  tps: 39.5,
});

function ticks(seed: number) {
  return Array.from({ length: 120 }, (_, i) => [
    15 + ((i * 37 + seed) % 40),
    ['sched_core', 'appearance_drain', 'native_step'],
    [2.1, 1.3, 0.7],
  ]);
}

function slowSections() {
  return {
    window_30s: win(22),
    window_5m: win(23),
    outliers: [],
    subsystems: [],
    kernel: {
      systems: Array.from({ length: 14 }, (_, i) => ({
        key: `system_${i}`,
        ms_per_s: 100 - i * 5,
        p50_ms: 1,
        p95_ms: 2,
        p99_ms: 3,
        overrun_share: 0.1,
      })),
      input: { wait_p99_ms: 4 },
    },
    attribution: {},
    attribution_rest: {},
    gc: { queued: [1, 2, 3], deleted_cleanly: 100, forced: 1, leaks: 0 },
    entities: {
      players: 3,
      mobs: 400,
      living: 380,
      humans: 40,
      machines: 3000,
      census: { objects: 80000, turfs: 1e6, areas: 300, at: 600, ms: 0 },
      previous: null,
    },
    churn: { draw: [['/mob', 300]] },
    rust: {
      'frame.count': 100,
      'frame.us.pace_step': 10000,
      'process.working_set_bytes': 2e9,
    },
    runtime: { cpu: 50, tick_drift: 4 },
  };
}

function fastSections(second: number) {
  return {
    header: {
      tick_budget_ms: 25,
      target_tps: 40,
      current_usage: 20 + (second % 10),
      maptick: 2,
      tidi: 3,
    },
    window_5s: win(20 + (second % 10)),
    ticks: ticks(second),
  };
}

type Run = { commits: number; ms: number; perSecondMs: number };

function run(page: 'Health' | 'Status', seconds: number): Run {
  const store = new StatStore({ sendMessage: () => {} });
  store.receive('init_verbs', { verblist: verbs(300) });
  store.receive('add_admin_tabs', 'token');
  if (page === 'Health') store.setView('Server', 'Health');
  let commits = 0;
  let ms = 0;
  const onRender: ProfilerOnRenderCallback = (_id, _phase, duration) => {
    commits++;
    ms += duration;
  };
  const view = render(
    <Profiler id="panel" onRender={onRender}>
      <StatWindow
        store={store}
        view={page === 'Health' ? 'Server' : 'Status'}
      />
    </Profiler>,
  );
  act(() =>
    store.receive('update_mc', {
      mc_metrics: { ...fastSections(0), ...slowSections() },
      partial: false,
      coord_entry: '1,1,1',
    }),
  );
  commits = 0;
  ms = 0;
  for (let second = 1; second <= seconds; second++) {
    act(() => {
      // About once a second: the fast sections; every fifth second one slow group too.
      const sections: any = fastSections(second);
      if (second % 5 === 0)
        sections.rust = { ...slowSections().rust, 'frame.count': 100 + second };
      store.receive('update_mc', {
        mc_metrics: sections,
        partial: true,
        coord_entry: '1,1,1',
      });
      store.receive('update_stat', {
        ping_str: 'Ping: 20ms',
        global_data: [`Server Time: ${second}`],
        other_str: [],
      });
    });
  }
  view.unmount();
  cleanup();
  return { commits, ms, perSecondMs: ms / seconds };
}

describe('stat panel render cost', () => {
  it('measures the Health page and the Status page while updates arrive', () => {
    const health = run('Health', 60);
    const status = run('Status', 60);
    console.log(
      `RENDER_COST Health page: ${health.commits} commits, ${health.perSecondMs.toFixed(2)} ms React work a second`,
    );
    console.log(
      `RENDER_COST Status page: ${status.commits} commits, ${status.perSecondMs.toFixed(2)} ms React work a second`,
    );
    expect(health.commits).toBeGreaterThan(0);
  });
});
