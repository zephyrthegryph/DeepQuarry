// The cost of a Status push on the page: an unchanged one makes no new state (nothing re-renders), and the tab bar a changed one would
// rebuild is measured beside it (App memoizes it on the verbs, so a status push no longer pays it).
import { describe, expect, it } from 'bun:test';
import { StatStore, type Verb, visibleTabs } from './store';

const host = { sendMessage: () => {} };
const status = (time: string) => ({
  ping_str: 'Ping: 20ms',
  global_data: ['Map: x', `Server Time: ${time}`],
  other_str: ['Combat mode: off'],
});

describe('status push', () => {
  it('an unchanged status push leaves the state alone', () => {
    const store = new StatStore(host);
    store.receive('update_stat', status('1'));
    const version = store.state.version;
    store.receive('update_stat', status('1'));
    expect(store.state.version).toBe(version);
    store.receive('update_stat', status('2'));
    expect(store.state.version).toBe(version + 1);
  });

  it('measures the tab bar a re-render rebuilt', () => {
    const store = new StatStore(host);
    const verbs: Verb[] = [];
    for (let i = 0; i < 600; i++) verbs.push([`Cat${i % 12}`, `Verb ${i}`]);
    store.receive('init_verbs', { verblist: verbs });
    const n = 200;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) visibleTabs(store.state);
    const tabsMs = (performance.now() - t0) / n;
    const t1 = performance.now();
    for (let i = 0; i < n; i++) store.receive('update_stat', status('1'));
    const sameMs = (performance.now() - t1) / n;
    console.log(
      `UI_PUSH_COST page: tab bar ${tabsMs.toFixed(4)} ms/render (600 verbs), unchanged status push ${sameMs.toFixed(4)} ms`,
    );
    expect(sameMs).toBeLessThan(5);
  });
});
