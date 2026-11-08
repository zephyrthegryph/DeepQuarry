import { afterEach, beforeEach, describe, expect, it } from 'bun:test';
import { gameDataAtom } from 'tgui/events/store';
import { CHAT_WINDOW, ColumnHost, decodeRaw, statWindowId } from './host';

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
  it('starts with the chat as its only window', () => {
    const host = new ColumnHost();
    expect(Object.keys(host.state.windows)).toEqual([CHAT_WINDOW]);
    expect(host.state.groups).toHaveLength(1);
  });

  it('opens a docked interface, routes its messages to its own store, and names it from its first update', () => {
    const host = new ColumnHost();
    host.receive('col/open', { wid: 'col-1', kind: 'tgui' });
    expect(forWindow('col-1')).toEqual([
      {
        type: 'col/msg',
        payload: { wid: 'col-1', type: 'ready', payload: {} },
      },
    ]);
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

  it('shows the stat panel views as one stack that follows the panel view', () => {
    const host = new ColumnHost();
    host.receive('col/open', { wid: 'statbrowser', kind: 'stat' });
    expect(forWindow('statbrowser').map((m) => m.payload.type)).toEqual([
      'ready',
      'Set-Tab',
      'Update-Verbs',
    ]);
    const stat = Object.values(host.state.windows).filter(
      (w) => w.kind === 'stat',
    );
    expect(stat.length).toBeGreaterThan(1);
    const stack = host.state.groups.find((g) =>
      g.windows.includes(statWindowId('Status')),
    );
    expect(stack?.windows.length).toBe(stat.length);
    expect(host.state.groups[0].id).toBe(stack?.id ?? '');
    expect(host.state.groups.at(-1)?.windows).toEqual([CHAT_WINDOW]);
    host.activate(statWindowId('Actions'));
    expect(host.stat.store.state.view).toBe('Actions');
    expect(
      stack && host.state.groups.find((g) => g.id === stack.id)?.active,
    ).toBe(statWindowId('Actions'));
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
