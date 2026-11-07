import { describe, expect, it } from 'bun:test';

import { dockPosition, HOTBAR_RESERVE } from './dock';

const map = { x: 100, y: 50, w: 1000, h: 700 };

describe('dockPosition', () => {
  it('centres on the map, above the hotbar reserve', () => {
    expect(dockPosition(map, { w: 360, h: 30 })).toEqual({
      x: 100 + 320,
      y: 50 + 700 - HOTBAR_RESERVE - 30,
    });
  });

  it('grows upward: a taller window keeps its bottom edge', () => {
    const small = dockPosition(map, { w: 360, h: 30 });
    const tall = dockPosition(map, { w: 360, h: 110 });
    expect(small.y + 30).toBe(tall.y + 110);
  });

  it('stays inside the map when the window is wider or taller than it', () => {
    expect(dockPosition(map, { w: 2000, h: 2000 })).toEqual({ x: 100, y: 50 });
  });
});
