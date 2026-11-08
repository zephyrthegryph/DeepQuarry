// The column under strain (host.ts, Column.tsx): open and close storms, many docked windows, a page reload in the middle of a drag.
import './requireContext.testing';
import { afterAll, beforeAll, describe, expect, it } from 'bun:test';
import { act, cleanup, fireEvent, render } from '@testing-library/react';
import { Provider } from 'jotai';
import { store } from '../events/store';

const { Column } = await import('./Column');
const { ColumnHost, columnHost } = await import('./host');

const byond = (globalThis as any).Byond;
const saved = { sendMessage: byond.sendMessage, error: console.error };
let sent: { type: string; payload: any }[] = [];
let errors: unknown[][] = [];

beforeAll(() => {
  byond.sendMessage = (type: string, payload: unknown) =>
    sent.push({ type, payload });
  console.error = (...args: unknown[]) => {
    errors.push(args);
  };
});
afterAll(() => {
  cleanup();
  setPageHeight(768);
  byond.sendMessage = saved.sendMessage;
  console.error = saved.error;
});

const named = (
  host: InstanceType<typeof ColumnHost>,
  wid: string,
  iface: string,
) =>
  host.receive('col/msg', {
    wid,
    type: 'update',
    payload: { config: { interface: { name: iface }, title: iface }, data: {} },
  });

/** The page's height as a resized client reports it. */
function setPageHeight(height: number) {
  Object.defineProperty(window, 'innerHeight', {
    value: height,
    configurable: true,
    writable: true,
  });
}

/** The page's column with nothing in it (other test files share the page's one host). */
function clearColumn() {
  for (const wid of Object.keys(columnHost.state.windows)) {
    columnHost.receive('col/close', { wid });
  }
}

/** Every window in the model is in exactly one group, every group holds only open windows, and the active one is its own. */
function consistent(host: InstanceType<typeof ColumnHost>) {
  const { windows, groups } = host.state;
  const placed = groups.flatMap((g) => g.windows);
  expect(new Set(placed).size).toBe(placed.length);
  expect(placed.sort()).toEqual(Object.keys(windows).sort());
  for (const group of groups) {
    expect(group.windows.length).toBeGreaterThan(0);
    expect(group.windows).toContain(group.active);
  }
  for (const wid of host.backends.keys()) expect(windows[wid]).toBeTruthy();
}

describe('an open and close storm', () => {
  it('50 interfaces opened and closed fast, in every order, leave a consistent column', () => {
    const host = new ColumnHost();
    for (let i = 0; i < 50; i++) {
      const wid = `tgui-window-${i}`;
      host.receive('col/open', { wid, kind: 'tgui' });
      // Some are named, some close before their first update, some get messages after they close, some open twice.
      if (i % 3 !== 0) named(host, wid, `Iface${i % 7}`);
      if (i % 4 === 0) host.receive('col/open', { wid, kind: 'tgui' });
      if (i % 2 === 0) host.receive('col/close', { wid });
      if (i % 5 === 0) named(host, wid, 'Late');
      if (i % 6 === 0) host.receive('col/close', { wid });
      consistent(host);
    }
    for (let i = 1; i < 50; i += 2)
      host.receive('col/close', { wid: `tgui-window-${i}` });
    consistent(host);
    expect(Object.keys(host.state.windows)).toEqual([]);
    expect(host.backends.size).toBe(0);
    // A late message for any of them reaches nothing and breaks nothing.
    for (let i = 0; i < 50; i++) named(host, `tgui-window-${i}`, 'Late');
    expect(Object.keys(host.state.windows)).toEqual([]);
  });
});

describe('many docked windows', () => {
  it('draws 25 docked windows, the chat last and filling, without an error', () => {
    errors = [];
    act(() => clearColumn());
    const page = render(
      <Provider store={store}>
        <Column />
      </Provider>,
    );
    act(() => {
      for (let i = 0; i < 25; i++) {
        const wid = `many-${i}`;
        columnHost.receive('col/open', { wid, kind: 'tgui' });
        named(columnHost, wid, i === 0 ? 'Chat' : `Many${i}`);
      }
    });
    consistent(columnHost);
    const groups = page.container.querySelectorAll('[data-column-group]');
    expect(groups.length).toBe(25);
    expect(groups[groups.length - 1].className).toContain('column-group--fill');
    expect(errors).toEqual([]);
    // The column at its least and its most: the entries are drawn cut to fit, never under their least, and whole again when tall.
    const drawn = () =>
      Array.from(groups)
        .slice(0, -1)
        .map((g) => Number.parseInt((g as HTMLElement).style.height, 10));
    act(() => {
      setPageHeight(200);
      window.dispatchEvent(new Event('resize'));
    });
    for (const h of drawn()) expect(h).toBe(80);
    act(() => {
      setPageHeight(20000);
      window.dispatchEvent(new Event('resize'));
    });
    for (const h of drawn()) expect(h).toBe(260);
    act(() => {
      for (let i = 0; i < 25; i++)
        columnHost.receive('col/close', { wid: `many-${i}` });
    });
    consistent(columnHost);
  });
});

describe('a page reload in the middle of a drag', () => {
  it('a drag whose window closed or whose page reloaded ends without an error or a stray float', () => {
    errors = [];
    act(() => clearColumn());
    const page = render(
      <Provider store={store}>
        <Column />
      </Provider>,
    );
    act(() => {
      for (const wid of ['drag-a', 'drag-b']) {
        columnHost.receive('col/open', { wid, kind: 'tgui' });
        named(columnHost, wid, wid);
      }
    });
    const head =
      page.container.querySelector<HTMLElement>(`[data-column-head]`)!;
    sent = [];
    act(() => {
      fireEvent.pointerDown(head, {
        button: 0,
        pointerId: 7,
        clientX: 50,
        clientY: 10,
      });
      fireEvent.pointerMove(document, {
        pointerId: 7,
        clientX: 50,
        clientY: 60,
      });
      fireEvent.pointerMove(document, {
        pointerId: 7,
        clientX: -500,
        clientY: 60,
      });
    });
    // The page reloads its layout and the dragged window closes while the pointer is still down.
    act(() => {
      columnHost.receive('col/init', { saved: '' });
      columnHost.receive('col/close', { wid: 'drag-a' });
      columnHost.receive('col/close', { wid: 'drag-b' });
    });
    act(() => {
      fireEvent.pointerUp(document, {
        pointerId: 7,
        clientX: -500,
        clientY: 60,
      });
    });
    expect(errors).toEqual([]);
    // Nothing floats a window that is gone.
    expect(sent.filter((m) => m.payload?.type === 'wm/float')).toEqual([]);
    consistent(columnHost);
  });
});
