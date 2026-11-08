import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { waitFor } from '@testing-library/react';
import { gameDataAtom } from 'tgui/events/store';
import { CHAT_PENDING, ColumnHost, decodeRaw } from './host';

const byond = (globalThis as any).Byond;
const original = byond.sendMessage;
let sent: any[] = [];

beforeEach(() => {
  sent = [];
  byond.sendMessage = (type: string, payload: any) =>
    sent.push({ type, payload });
});
afterEach(() => {
  byond.sendMessage = original;
});

/** A server message as the column page receives it for window `wid` (TGUI_CREATE_MESSAGE's format, url-encoded). */
const raw = (type: string, payload: unknown) =>
  encodeURIComponent(JSON.stringify({ type, payload }));

const forWindow = (wid: string) =>
  sent.filter((m) => m.type === 'col/msg' && m.payload.wid === wid);

describe('the column page', () => {
  it('starts empty: the chat and the stat panel are server windows like any other', () => {
    const host = new ColumnHost();
    expect(Object.keys(host.state.windows)).toEqual([]);
    expect(host.state.groups).toHaveLength(0);
  });

  it('opens a docked interface, routes its messages to its own store, and names it from its first update', () => {
    const host = new ColumnHost();
    host.receive('col/open', { wid: 'col-1', kind: 'tgui' });
    expect(forWindow('col-1')).toContainEqual({
      type: 'col/msg',
      payload: { wid: 'col-1', type: 'ready', payload: {} },
    });
    host.receive('col/msg', {
      wid: 'col-1',
      raw: raw('update', {
        config: { interface: { name: 'Pda' }, title: 'PDA' },
        data: { owner: 'Nick' },
      }),
    });
    const backend = host.backends.get('col-1')!;
    expect(backend.store.get(gameDataAtom)).toEqual({ owner: 'Nick' });
    expect(host.state.windows['col-1']).toMatchObject({
      iface: 'Pda',
      title: 'PDA',
      kind: 'tgui',
    });
    // It acts on its own channel, wrapped for its id.
    backend.send('act/select', { app: 'notes' });
    expect(forWindow('col-1').at(-1)).toEqual({
      type: 'col/msg',
      payload: { wid: 'col-1', type: 'act/select', payload: { app: 'notes' } },
    });
  });

  it('answers a window ping and drops a closed window', () => {
    const host = new ColumnHost();
    host.receive('col/open', { wid: 'col-2', kind: 'tgui' });
    host.receive('col/msg', { wid: 'col-2', raw: raw('ping', { n: 1 }) });
    expect(forWindow('col-2').at(-1)?.payload).toEqual({
      wid: 'col-2',
      type: 'ping/reply',
      payload: { n: 1 },
    });
    host.receive('col/close', { wid: 'col-2' });
    expect(host.state.windows['col-2']).toBeUndefined();
    expect(host.backends.has('col-2')).toBe(false);
    // A late message for it reaches nothing.
    expect(() =>
      host.receive('col/msg', { wid: 'col-2', raw: raw('update', {}) }),
    ).not.toThrow();
  });

  it('docks the stat panel like any other window: its own entry', () => {
    const host = new ColumnHost();
    host.receive('col/open', { wid: 'col-1', kind: 'tgui' });
    host.receive('col/msg', {
      wid: 'col-1',
      raw: raw('update', {
        config: { interface: { name: 'StatPanel' }, title: 'Status' },
      }),
    });
    expect(host.state.windows['col-1']).toMatchObject({
      iface: 'StatPanel',
      title: 'Status',
      kind: 'tgui',
    });
    expect(host.state.groups.map((g) => g.windows)).toEqual([['col-1']]);
    // Its own protocol's messages reach its window's listeners (useWindowMessages).
    const got: unknown[] = [];
    host.backends
      .get('col-1')!
      .listeners.add((type, payload) => got.push([type, payload]));
    host.receive('col/msg', {
      wid: 'col-1',
      raw: raw('update_verbs', { n: 1 }),
    });
    expect(got).toEqual([['update_verbs', { n: 1 }]]);
  });

  it('tells the server which docked windows are off screen: a background tab, a collapsed entry', () => {
    const host = new ColumnHost();
    host.receive('col/open', { wid: 'col-1', kind: 'tgui' });
    host.receive('col/open', { wid: 'col-2', kind: 'tgui' });
    const views = (wid: string) =>
      forWindow(wid)
        .filter((m) => m.payload.type === 'wm/view')
        .map((m) => m.payload.payload.hidden);
    // Each alone in its entry: both shown.
    expect(views('col-1')).toEqual([false]);
    expect(views('col-2')).toEqual([false]);
    const of = (wid: string) =>
      host.state.groups.find((g) => g.windows.includes(wid))!;
    // Stacked: the stack shows col-1 (the dropped one is active), col-2 behind it... whichever is not active is hidden.
    host.dispatch({
      type: 'joinGroup',
      group: of('col-2').id,
      into: of('col-1').id,
    });
    const stack = of('col-1');
    const behind = stack.windows.find((w) => w !== stack.active)!;
    expect(views(behind).at(-1)).toBe(true);
    expect(views(stack.active).at(-1)).toBe(false);
    // Collapsed: both hidden; expanded again: the active one is shown, once.
    host.dispatch({ type: 'collapse', group: stack.id, collapsed: true });
    expect(views(stack.active).at(-1)).toBe(true);
    const before = views(behind).length;
    host.dispatch({ type: 'collapse', group: stack.id, collapsed: false });
    expect(views(stack.active).at(-1)).toBe(false);
    expect(views(behind).length).toBe(before);
    // Switching tabs swaps which one is fed.
    host.activate(behind);
    expect(views(behind).at(-1)).toBe(false);
  });

  it('decodes only well-formed window messages', () => {
    expect(decodeRaw(raw('update', { a: 1 }))).toEqual({
      type: 'update',
      payload: { a: 1 },
    });
    expect(decodeRaw('%7Bbroken')).toBeNull();
    expect(decodeRaw(5)).toBeNull();
  });
});

describe('the chat at login', () => {
  const chatUpdate = (wid: string) => ({
    wid,
    raw: raw('update', {
      config: { interface: { name: 'Chat' }, title: 'Chat' },
      data: { draft: '', session: 's1' },
    }),
  });

  it('stands in for the chat from the first moment, and the Chat window takes its place', async () => {
    const host = new ColumnHost();
    host.receive('col/open', { wid: 'col-stat', kind: 'tgui' });
    host.receive('col/msg', {
      wid: 'col-stat',
      raw: raw('update', {
        config: { interface: { name: 'StatPanel' }, title: 'Status' },
      }),
    });
    host.receive('col/init', { saved: '' });
    // The page's own chat, docked where the Chat window will be, before the server's window arrives.
    expect(host.state.windows[CHAT_PENDING]).toMatchObject({
      iface: 'Chat',
      kind: 'pending',
    });
    expect(host.state.groups.map((g) => g.windows)).toEqual([
      ['col-stat'],
      [CHAT_PENDING],
    ]);
    host.receive('col/open', { wid: 'col-chat', kind: 'tgui' });
    host.receive('col/msg', chatUpdate('col-chat'));
    await waitFor(() =>
      expect(host.state.windows[CHAT_PENDING]).toBeUndefined(),
    );
    // In the stand-in's place, not wherever its window first landed.
    expect(host.state.groups.map((g) => g.windows)).toEqual([
      ['col-stat'],
      ['col-chat'],
    ]);
    expect(host.state.windows['col-chat']).toMatchObject({
      iface: 'Chat',
      kind: 'tgui',
    });
  });

  it('has no stand-in for a chat the player floated', () => {
    const host = new ColumnHost();
    host.receive('col/init', {
      saved: JSON.stringify({ Chat: { dock: false, group: 'g1' } }),
    });
    expect(host.state.windows[CHAT_PENDING]).toBeUndefined();
  });
});
