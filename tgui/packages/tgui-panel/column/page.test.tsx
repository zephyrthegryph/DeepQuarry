// The right-hand column's page as the client loads it (happy-dom): the chat renders in its window, the stat panel's views stack, a
// docked interface renders from its own messages, drops are judged in the page, and nothing logs an error.
import {
  afterAll,
  afterEach,
  beforeAll,
  describe,
  expect,
  it,
  mock,
} from 'bun:test';
import { act, cleanup, render, waitFor } from '@testing-library/react';
import { Provider, useAtomValue } from 'jotai';
import { useBackend } from 'tgui/backend';
import { type EmbeddedBackend, EmbeddedContext } from 'tgui/embedded';
import { configAtom } from 'tgui/events/store';
import { store } from '../events/store';

// routes.tsx finds interface modules with webpack's require.context, which only exists in the bundle; its lookup is the same one native
// windows use. Here only that lookup is stood in for (the PDA by name); the embedding itself (own store, context, wrapper) is the real one.
mock.module('tgui/routes', () => ({
  RoutingErrorWindow: () => null,
  EmbeddedInterface(props: { backend: EmbeddedBackend }) {
    return (
      <Provider store={props.backend.store}>
        <EmbeddedContext.Provider value={props.backend}>
          <div className="EmbeddedInterface">
            <Routed />
          </div>
        </EmbeddedContext.Provider>
      </Provider>
    );
  },
}));

/** A stand-in interface (the real PDA finds its screens with require.context too): it reads its own window's data through useBackend. */
function ProbeInterface() {
  const { data, act } = useBackend<{ owner: string }>();
  return (
    <button type="button" onClick={() => act('select', { app: 'notes' })}>
      PDA of {data.owner}
    </button>
  );
}

function Routed() {
  const name = useAtomValue(configAtom)?.interface?.name;
  return name === 'Pda' ? <ProbeInterface /> : null;
}

const { Column } = await import('./Column');
const { columnHost } = await import('./host');

const byond = (globalThis as any).Byond;
const saved = {
  sendMessage: byond.sendMessage,
  winget: byond.winget,
  error: console.error,
};
let sent: any[] = [];
let errors: unknown[][] = [];

/** The main window and the column as BYOND reports them: a 2000x1000 client area, the column its right 600 px. */
async function winget(id: string, props: unknown) {
  if (id === 'mainwindow') {
    return {
      pos: { x: 0, y: 0 },
      'outer-size': { x: 2000, y: 1000 },
      size: { x: 2000, y: 1000 },
      'inner-size': { x: 2000, y: 1000 },
      'is-maximized': false,
    };
  }
  if (id === 'rpane.rpanewindow' && props === 'size') {
    return { x: 600, y: 1000 };
  }
  return {};
}

beforeAll(() => {
  byond.sendMessage = (type: string, payload: unknown) =>
    sent.push({ type, payload });
  byond.winget = winget;
  console.error = (...args: unknown[]) => {
    errors.push(args);
  };
});
afterAll(() => {
  byond.sendMessage = saved.sendMessage;
  byond.winget = saved.winget;
  console.error = saved.error;
});
afterEach(() => {
  cleanup();
  sent = [];
});

const raw = (type: string, payload: unknown) =>
  encodeURIComponent(JSON.stringify({ type, payload }));

function renderPage() {
  return render(
    <Provider store={store}>
      <Column />
    </Provider>,
  );
}

describe('the column page', () => {
  it('renders the chat in its window, the stat views as one stack above it, and a docked PDA from its own messages', async () => {
    errors = [];
    const page = renderPage();
    // The chat: its tab row and its input, inside a column window (tgui layouts are mocked in tests, so its Pane is a plain box).
    expect(
      page.container.querySelector('.column-window .ChatTabs'),
    ).toBeTruthy();
    expect(
      page.container.querySelector('.column-window [data-chat-input]'),
    ).toBeTruthy();
    act(() => {
      columnHost.receive('col/open', { wid: 'statbrowser', kind: 'stat' });
      columnHost.receive('col/msg', {
        wid: 'statbrowser',
        raw: raw('init_verbs', { verblist: [['IC', 'Say', 'say']] }),
      });
    });
    const groups = () =>
      Array.from(page.container.querySelectorAll('[data-column-group]'));
    expect(groups()).toHaveLength(2);
    // The stat views stack first, as tabs; the chat fills the rest below.
    expect(groups()[0].textContent).toContain('Status');
    expect(groups()[1].querySelector('.ChatTabs')).toBeTruthy();
    expect(groups()[1].className).toContain('column-group--fill');
    // A docked PDA: opened by the server, named and drawn from its own update.
    act(() => {
      columnHost.receive('col/open', { wid: 'col-7', kind: 'tgui' });
      columnHost.receive('col/msg', {
        wid: 'col-7',
        raw: raw('update', {
          config: { interface: { name: 'Pda' }, title: 'PDA', status: 2 },
          data: { owner: 'Nick Price' },
        }),
      });
    });
    await waitFor(() =>
      expect(page.container.querySelector('.EmbeddedInterface')).toBeTruthy(),
    );
    expect(page.container.textContent).toContain('PDA of Nick Price');
    // Its act goes out on its own window id.
    act(() => {
      (
        page.container.querySelector('.EmbeddedInterface button') as HTMLElement
      ).click();
    });
    expect(sent.at(-1)).toEqual({
      type: 'col/msg',
      payload: { wid: 'col-7', type: 'act/select', payload: { app: 'notes' } },
    });
    expect(
      sent.filter((m) => m.payload?.wid === 'col-7').map((m) => m.payload.type),
    ).toContain('ready');
    // Its float and close buttons are on its header; the chat and the stat panel have none (they have no native window to go to).
    const pda = groups().find((g) => g.textContent?.includes('PDA'))!;
    expect(pda.querySelectorAll('.Button').length).toBeGreaterThanOrEqual(3);
    expect(errors).toEqual([]);
    act(() => columnHost.receive('col/close', { wid: 'col-7' }));
    expect(groups().some((g) => g.textContent?.includes('PDA'))).toBe(false);
  });
});

describe('a native window dropped on the column', () => {
  const answered = () =>
    sent.filter((m) => m.type === 'col/msg' && m.payload.type === 'WM-Drop');

  it('docks at the list index the drop point falls at, judged in the page', async () => {
    columnHost.receive('col/drop-check', {
      wid: 'tgui-window-3',
      x: 1500,
      y: 500,
    });
    await waitFor(() => expect(answered()).toHaveLength(1));
    expect(answered()[0].payload).toMatchObject({
      wid: 'statbrowser',
      payload: { wid: 'tgui-window-3' },
    });
    expect(typeof answered()[0].payload.payload.index).toBe('number');
  });

  it('does nothing for a drop over the map', async () => {
    columnHost.receive('col/drop-check', {
      wid: 'tgui-window-3',
      x: 300,
      y: 500,
    });
    await waitFor(() =>
      expect(
        sent.some(
          (m) =>
            m.payload?.type === 'WM-Log' &&
            m.payload.payload.drop === 'outside',
        ),
      ).toBe(true),
    );
    expect(answered()).toHaveLength(0);
  });
});
