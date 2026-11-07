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

describe('watchDock', () => {
  it('runs on the skin resize message, never on a timer, and stops when closed', async () => {
    const { DOCK_RESIZED, onDockResized, watchDock } = await import('./dock');
    const listeners: Record<string, (payload: unknown) => void> = {};
    const wingets: string[] = [];
    const winsets: Record<string, string>[] = [];
    (globalThis as any).Byond = {
      subscribeTo: (type: string, fn: (payload: unknown) => void) => {
        listeners[type] = fn;
      },
      winget: async (id: string, prop: string) => {
        wingets.push(`${id}.${prop}`);
        return { x: 10, y: 10 };
      },
      winset: (_id: null, props: Record<string, string>) => {
        winsets.push(props);
      },
    };
    const realSetInterval = globalThis.setInterval;
    let intervals = 0;
    globalThis.setInterval = ((...args: any[]) => {
      intervals++;
      return (realSetInterval as any)(...args);
    }) as typeof setInterval;
    try {
      const stop = watchDock(
        () => ({ w: 360, h: 30 }),
        () => 1,
      );
      expect(intervals).toBe(0);
      expect(typeof listeners[DOCK_RESIZED]).toBe('function');
      expect(wingets.length).toBe(0);
      await onDockResized();
      expect(wingets[0]).toBe('tgui_say.size');
      expect(winsets.length).toBeGreaterThan(0); // 10x10 is under the minimum: restored
      stop();
      const before = wingets.length;
      await onDockResized();
      expect(wingets.length).toBe(before);
    } finally {
      globalThis.setInterval = realSetInterval;
    }
  });
});
