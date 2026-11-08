import { afterEach, describe, expect, it } from 'bun:test';
import { DockHost } from './dockHost';

const rectNode = (rect: {
  left: number;
  top: number;
  w: number;
  h: number;
}) => {
  const node = document.createElement('div');
  node.getBoundingClientRect = () =>
    ({
      left: rect.left,
      top: rect.top,
      right: rect.left + rect.w,
      bottom: rect.top + rect.h,
      width: rect.w,
      height: rect.h,
      x: rect.left,
      y: rect.top,
    }) as DOMRect;
  return node;
};

const byond = (globalThis as any).Byond;
const original = { winget: byond.winget, winset: byond.winset };

afterEach(() => {
  byond.winget = original.winget;
  byond.winset = original.winset;
});

describe('dock host placement', () => {
  it('shows a docked window over its body, addressed by its own id', async () => {
    const sets: unknown[][] = [];
    byond.winget = async (id: string) =>
      id === 'statwindow' ? { x: 100, y: 50 } : 'statwindow';
    byond.winset = (...args: unknown[]) => sets.push(args);
    const host = new DockHost();
    host.receive('wm/open', {
      id: 'tgui-window-3',
      interface: 'Pda',
      title: 'Personal Data Assistant',
    });
    host.setArea(rectNode({ left: 0, top: 0, w: 300, h: 600 }));
    host.setBody(
      'tgui-window-3',
      rectNode({ left: 10, top: 20, w: 200, h: 150 }),
    );
    await new Promise((resolve) => setTimeout(resolve, 0));
    host.placeNow();
    const placed = sets.filter((args) => args[0] === 'tgui-window-3');
    expect(placed.at(-1)).toEqual([
      'tgui-window-3',
      { pos: '110,70', size: '200x150', alpha: 255, 'is-visible': true },
    ]);
    // Every winset names its window: a bulk call with no id is never sent.
    expect(sets.every((args) => typeof args[0] === 'string')).toBe(true);
  });

  it('hides a collapsed window, then sends nothing while nothing changes', async () => {
    const sets: unknown[][] = [];
    byond.winget = async (id: string) =>
      id === 'statwindow' ? { x: 0, y: 0 } : 'statwindow';
    byond.winset = (...args: unknown[]) => sets.push(args);
    const host = new DockHost();
    host.receive('wm/open', { id: 'w1', interface: 'APC', title: 'APC' });
    host.setArea(rectNode({ left: 0, top: 0, w: 300, h: 600 }));
    host.setBody('w1', rectNode({ left: 0, top: 0, w: 200, h: 150 }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    host.dispatch({
      type: 'collapse',
      group: host.state.groups[0].id,
      collapsed: true,
    });
    host.placeNow();
    expect(sets.filter((a) => a[0] === 'w1').at(-1)).toEqual([
      'w1',
      { 'is-visible': false },
    ]);
    const before = sets.length;
    host.placeNow();
    expect(sets.length).toBe(before);
  });
});
