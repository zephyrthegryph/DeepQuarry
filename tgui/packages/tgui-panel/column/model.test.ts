import { describe, expect, it } from 'bun:test';
import {
  COLUMN_GAP,
  COLUMN_HEAD,
  COLUMN_PAD,
  DOCK_HEIGHT_MIN,
  DOCK_SAVE_MAX,
  type DockState,
  dockReduce,
  emptyDock,
  FILL_MIN,
  FIT_MIN,
  fitHeights,
  hiddenIds,
  parseSaved,
  serializeSaved,
  shownIds,
  fillHeight,
} from './model';

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

  it('keeps a window with no interface yet out of the saved layout', () => {
    let state = emptyDock();
    state = dockReduce(state, {
      type: 'open',
      window: { id: 'col-1', iface: '', title: '' },
    });
    state = dockReduce(state, { type: 'open', window: win('a') });
    expect(Object.keys(state.saved)).toEqual(['A']);
    expect(state.groups).toHaveLength(2);
  });

  it('scrubs column window ids from a loaded layout', () => {
    const place = { dock: true, group: 'g1', order: 0, tab: 0 };
    const text = JSON.stringify({
      'col-1': place,
      'col-12': place,
      Pda: place,
    });
    expect(Object.keys(parseSaved(text))).toEqual(['Pda']);
    const loaded = dockReduce(emptyDock(), {
      type: 'load',
      saved: { 'col-3': parseSaved(text).Pda, Pda: parseSaved(text).Pda },
    });
    expect(Object.keys(loaded.saved)).toEqual(['Pda']);
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

describe('fitting the entries to the column', () => {
  const group = (id: string, height: number, collapsed = false) => ({
    id,
    windows: [id],
    active: id,
    collapsed,
    height,
  });

  it('keeps a sized filling entry its height; an unsized one only the least', () => {
    expect(fillHeight(group('chat', 500))).toBe(160);
    expect(fillHeight({ ...group('chat', 500), sized: true })).toBe(500);
    expect(fillHeight({ ...group('chat', 90), sized: true })).toBe(160);
  });

  it('resizing any entry, the filling one included, marks it sized', () => {
    let state = dockReduce(emptyDock(), {
      type: 'open',
      window: { id: 'w', iface: 'Chat', title: 'Chat' },
    });
    state = dockReduce(state, {
      type: 'resize',
      group: state.groups[0].id,
      height: 400,
    });
    expect(state.groups[0].sized).toBe(true);
    expect(state.saved.Chat.sized).toBe(true);
  });

  it('keeps the saved heights while they fit, and gets them back on a taller column', () => {
    const groups = [group('a', 300), group('b', 200), group('chat', 260)];
    expect(fitHeights(groups, 2, 4000)).toEqual([300, 200, 260]);
  });

  it('cuts the entries in proportion on a short column, so the chat keeps its room', () => {
    const groups = [group('a', 300), group('b', 300), group('chat', 260)];
    const [a, b] = fitHeights(groups, 2, 600);
    expect(a).toBe(b);
    // The column's padding, two gaps, the chat's header and its least room, and the two entries: all within 600.
    expect(
      a + b + COLUMN_PAD + 2 * COLUMN_GAP + COLUMN_HEAD + FILL_MIN,
    ).toBeLessThanOrEqual(600);
    expect(groups[0].height).toBe(300);
  });

  it('collapses the border between neighbouring entries: the seam is an overlap of one border width', () => {
    expect(COLUMN_GAP).toBe(-3);
    const groups = [group('a', 300), group('b', 300), group('chat', 260)];
    // Two seams give two border widths back to the entries: the budget is 416, not 410.
    const [a, b] = fitHeights(groups, 2, 600);
    expect(a + b).toBeGreaterThan(410);
    expect(a + b).toBeLessThanOrEqual(416);
  });

  it('never cuts an entry under its least: 25 entries on a minimal column scroll instead', () => {
    const groups = Array.from({ length: 25 }, (_, i) => group(`g${i}`, 260));
    const heights = fitHeights(groups, 24, 200);
    for (const h of heights.slice(0, 24)) expect(h).toBe(FIT_MIN);
  });

  it('leaves collapsed entries alone', () => {
    const groups = [group('a', 500, true), group('b', 900), group('chat', 260)];
    const heights = fitHeights(groups, 2, 500);
    expect(heights[0]).toBe(500);
    expect(heights[1]).toBeLessThan(900);
  });

  describe('boundary drag and opening', () => {
    const iface = (id: string, name: string, height: number) => ({
      id,
      iface: name,
      title: name,
      height,
    });
    /** Status 300 over APC 200 over the chat (sized 260). */
    const column = () => {
      let state = emptyDock();
      state = dockReduce(state, {
        type: 'open',
        window: iface('s', 'StatPanel', 300),
      });
      state = dockReduce(state, {
        type: 'open',
        window: iface('a', 'APC', 200),
      });
      state = dockReduce(state, {
        type: 'open',
        window: { id: 'c', iface: 'Chat', title: 'Chat' },
      });
      return state;
    };
    const heights = (state: DockState) => state.groups.map((g) => g.height);

    it('dragging the Status/APC boundary resizes those two and never the chat', () => {
      const state = column();
      const [s, a, c] = state.groups;
      const next = dockReduce(state, {
        type: 'boundary',
        group: s.id,
        next: a.id,
        start: 300,
        nextStart: 200,
        dy: 50,
      });
      expect(heights(next)).toEqual([350, 150, c.height]);
      expect(next.groups[2]).toEqual(c);
    });

    it('a boundary drag keeps the pair total and stops at the least height', () => {
      const state = column();
      const [s, a] = state.groups;
      const next = dockReduce(state, {
        type: 'boundary',
        group: s.id,
        next: a.id,
        start: 300,
        nextStart: 200,
        dy: 1000,
      });
      expect(heights(next).slice(0, 2)).toEqual([500 - FIT_MIN, FIT_MIN]);
      const up = dockReduce(state, {
        type: 'boundary',
        group: s.id,
        next: a.id,
        start: 300,
        nextStart: 200,
        dy: -1000,
      });
      expect(heights(up).slice(0, 2)).toEqual([FIT_MIN, 500 - FIT_MIN]);
    });

    it('the boundary above the chat resizes only the entry over it', () => {
      const state = column();
      const [s, a, c] = state.groups;
      const next = dockReduce(state, {
        type: 'boundary',
        group: a.id,
        next: null,
        start: 200,
        nextStart: 0,
        dy: 40,
      });
      expect(heights(next)).toEqual([s.height, 240, c.height]);
    });

    it('a new entry takes its height from Status first', () => {
      let state = dockReduce(emptyDock(), {
        type: 'open',
        window: iface('s', 'StatPanel', 400),
      });
      state = dockReduce(state, {
        type: 'open',
        window: { id: 'c', iface: 'Chat', title: 'Chat' },
      });
      state = dockReduce(state, {
        type: 'open',
        window: { ...iface('a', 'APC', 150), at: 1 },
      });
      expect(order(state)).toEqual([['s'], ['a'], ['c']]);
      expect(heights(state).slice(0, 2)).toEqual([250, 150]);
    });

    it('takes from Status only down to its least, then from a sized chat', () => {
      let state = dockReduce(emptyDock(), {
        type: 'open',
        window: iface('s', 'StatPanel', 100),
      });
      state = dockReduce(state, {
        type: 'open',
        window: { id: 'c', iface: 'Chat', title: 'Chat' },
      });
      state = dockReduce(state, {
        type: 'resize',
        group: state.groups[1].id,
        height: 400,
      });
      state = dockReduce(state, {
        type: 'open',
        window: { ...iface('a', 'APC', 150), at: 1 },
      });
      // Status gives 20 (100 to 80); the chat gives the other 130 (400 to 270).
      expect(heights(state)).toEqual([FIT_MIN, 150, 270]);
    });

    it('a window reopened at its saved place takes nothing again', () => {
      const state = column();
      const before = heights(state);
      let next = dockReduce(state, { type: 'close', id: 'a' });
      next = dockReduce(next, {
        type: 'open',
        window: { id: 'a', iface: 'APC', title: 'APC' },
      });
      expect(heights(next)[0]).toBe(before[0]);
    });
  });
});
