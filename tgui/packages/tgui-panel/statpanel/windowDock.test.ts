import { describe, expect, it } from 'bun:test';
import {
  DOCK_HEIGHT_MIN,
  DOCK_SAVE_MAX,
  type DockState,
  dockReduce,
  emptyDock,
  hiddenIds,
  parseSaved,
  serializeSaved,
  shownIds,
} from './windowDock';

const win = (id: string, iface = id.toUpperCase()) => ({
  id,
  iface,
  title: iface,
});

function openAll(...ids: string[]): DockState {
  let state = emptyDock();
  for (const id of ids) {
    state = dockReduce(state, { type: 'open', window: win(id) });
  }
  return state;
}

const order = (state: DockState) => state.groups.map((g) => g.windows);

describe('window dock layout', () => {
  it('opens each window as its own list entry, in order', () => {
    const state = openAll('a', 'b', 'c');
    expect(order(state)).toEqual([['a'], ['b'], ['c']]);
    expect(shownIds(state)).toEqual(['a', 'b', 'c']);
    expect(hiddenIds(state)).toEqual([]);
  });

  it('a collapsed group hides its window (no pushes) and expanding shows it', () => {
    let state = openAll('a', 'b');
    const group = state.groups[0].id;
    state = dockReduce(state, { type: 'collapse', group, collapsed: true });
    expect(hiddenIds(state)).toEqual(['a']);
    expect(shownIds(state)).toEqual(['b']);
    state = dockReduce(state, { type: 'collapse', group, collapsed: false });
    expect(hiddenIds(state)).toEqual([]);
  });

  it('closing removes the window and its emptied group', () => {
    let state = openAll('a', 'b');
    state = dockReduce(state, { type: 'close', id: 'a' });
    expect(order(state)).toEqual([['b']]);
    expect(state.windows.a).toBeUndefined();
  });

  it('reorders groups', () => {
    let state = openAll('a', 'b', 'c');
    state = dockReduce(state, {
      type: 'moveGroup',
      group: state.groups[0].id,
      index: 3,
    });
    expect(order(state)).toEqual([['b'], ['c'], ['a']]);
    state = dockReduce(state, {
      type: 'moveGroup',
      group: state.groups[2].id,
      index: 0,
    });
    expect(order(state)).toEqual([['a'], ['b'], ['c']]);
  });

  it('stacks a window into another group as the active tab; the others hide', () => {
    let state = openAll('a', 'b', 'c');
    state = dockReduce(state, {
      type: 'moveWindow',
      id: 'c',
      group: state.groups[0].id,
      index: 1,
    });
    expect(order(state)).toEqual([['a', 'c'], ['b']]);
    expect(state.groups[0].active).toBe('c');
    expect(hiddenIds(state)).toEqual(['a']);
    state = dockReduce(state, { type: 'activate', id: 'a' });
    expect(hiddenIds(state)).toEqual(['c']);
  });

  it('reorders tabs inside a group', () => {
    let state = openAll('a', 'b', 'c');
    const g = state.groups[0].id;
    state = dockReduce(state, {
      type: 'moveWindow',
      id: 'b',
      group: g,
      index: 1,
    });
    state = dockReduce(state, {
      type: 'moveWindow',
      id: 'c',
      group: g,
      index: 2,
    });
    expect(order(state)).toEqual([['a', 'b', 'c']]);
    state = dockReduce(state, {
      type: 'moveWindow',
      id: 'a',
      group: g,
      index: 3,
    });
    expect(order(state)).toEqual([['b', 'c', 'a']]);
  });

  it('splits a tab out into its own entry', () => {
    let state = openAll('a', 'b');
    state = dockReduce(state, {
      type: 'moveWindow',
      id: 'b',
      group: state.groups[0].id,
      index: 1,
    });
    state = dockReduce(state, { type: 'splitWindow', id: 'a', index: 1 });
    expect(order(state)).toEqual([['b'], ['a']]);
    expect(hiddenIds(state)).toEqual([]);
  });

  it('closing the active tab activates its neighbour', () => {
    let state = openAll('a', 'b');
    state = dockReduce(state, {
      type: 'moveWindow',
      id: 'b',
      group: state.groups[0].id,
      index: 1,
    });
    state = dockReduce(state, { type: 'close', id: 'b' });
    expect(state.groups[0].active).toBe('a');
  });

  it('resizes within limits', () => {
    let state = openAll('a');
    const group = state.groups[0].id;
    state = dockReduce(state, { type: 'resize', group, height: 3 });
    expect(state.groups[0].height).toBe(DOCK_HEIGHT_MIN);
  });

  it('a reopened interface goes back to its group, place and tab', () => {
    let state = openAll('a', 'b', 'c');
    state = dockReduce(state, {
      type: 'moveWindow',
      id: 'c',
      group: state.groups[0].id,
      index: 0,
    });
    state = dockReduce(state, { type: 'close', id: 'c' });
    state = dockReduce(state, { type: 'open', window: win('z', 'C') });
    expect(order(state)).toEqual([['z', 'a'], ['b']]);
  });

  it('floating marks the interface undocked but keeps where it was', () => {
    let state = openAll('a');
    state = dockReduce(state, { type: 'float', id: 'a' });
    expect(state.groups).toEqual([]);
    expect(state.saved.A.dock).toBe(false);
  });

  it('round-trips the saved layout and survives junk', () => {
    let state = openAll('a', 'b');
    state = dockReduce(state, {
      type: 'collapse',
      group: state.groups[1].id,
      collapsed: true,
    });
    const text = serializeSaved(state.saved);
    const loaded = dockReduce(emptyDock(), {
      type: 'load',
      saved: parseSaved(text),
    });
    const again = dockReduce(
      dockReduce(loaded, { type: 'open', window: win('y', 'B') }),
      { type: 'open', window: win('x', 'A') },
    );
    expect(order(again)).toEqual([['x'], ['y']]);
    expect(again.groups[1].collapsed).toBe(true);
    expect(parseSaved('not json')).toEqual({});
    expect(parseSaved('{"A": 4}')).toEqual({});
  });

  it('keeps the saved text within the preference limit', () => {
    const saved: DockState['saved'] = {};
    for (let i = 0; i < 400; i++) {
      saved[`Interface${i}`] = {
        dock: i % 2 === 0,
        group: `g${i}`,
        order: i,
        tab: 0,
        collapsed: false,
        height: 260,
      };
    }
    const text = serializeSaved(saved);
    expect(text.length).toBeLessThanOrEqual(DOCK_SAVE_MAX);
    expect(Object.values(parseSaved(text)).every((p) => p.dock)).toBe(true);
  });
});

describe('one layout model: list, stacks and drops', () => {
  it('re-orders a stack’s tabs as the strip commits them', () => {
    let s = openAll('a', 'b', 'c');
    const into = s.groups[0].id;
    s = dockReduce(s, { type: 'joinGroup', group: s.groups[1].id, into });
    s = dockReduce(s, { type: 'joinGroup', group: s.groups[1].id, into });
    expect(s.groups[0].windows).toEqual(['a', 'b', 'c']);
    s = dockReduce(s, {
      type: 'orderTabs',
      group: into,
      order: ['c', 'a', 'b'],
    });
    expect(s.groups[0].windows).toEqual(['c', 'a', 'b']);
    expect(s.saved.C.tab).toBe(0);
    const same = dockReduce(s, {
      type: 'orderTabs',
      group: into,
      order: ['a'],
    });
    expect(same).toBe(s);
  });

  it('stacks a whole entry onto another and shows the dropped one', () => {
    let s = openAll('a', 'b');
    s = dockReduce(s, {
      type: 'collapse',
      group: s.groups[0].id,
      collapsed: true,
    });
    s = dockReduce(s, {
      type: 'joinGroup',
      group: s.groups[1].id,
      into: s.groups[0].id,
    });
    expect(s.groups).toHaveLength(1);
    expect(s.groups[0].active).toBe('b');
    expect(s.groups[0].collapsed).toBe(false);
  });

  it('puts a window dropped on the panel where it was dropped', () => {
    let s = openAll('a', 'b');
    s = dockReduce(s, { type: 'open', window: { ...win('c'), at: 1 } });
    expect(s.groups.map((g) => g.windows[0])).toEqual(['a', 'c', 'b']);
    expect(s.windows.c).toEqual(win('c'));
  });

  it('a drop point wins over the saved place', () => {
    let s = openAll('a', 'b', 'c');
    s = dockReduce(s, { type: 'close', id: 'c' });
    s = dockReduce(s, { type: 'open', window: { ...win('c'), at: 0 } });
    expect(s.groups[0].windows).toEqual(['c']);
  });
});
