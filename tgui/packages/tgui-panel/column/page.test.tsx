// The right-hand column's page as the client loads it (happy-dom): the chat renders in its window, the stat panel docks above it, a
// docked interface renders from its own messages, drops are judged in the page, and nothing logs an error.
import './requireContext.testing';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'bun:test';
import { act, cleanup, render, waitFor } from '@testing-library/react';
import { Provider } from 'jotai';
import { store } from '../events/store';

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

/** The server opens the stat panel as a docked tgui window (stat_panel_window.dm): a column window whose first update names it. */
function openStatPanel() {
  if (columnHost.backends.has('col-stat')) return;
  columnHost.receive('col/open', { wid: 'col-stat', kind: 'tgui' });
  columnHost.receive('col/msg', {
    wid: 'col-stat',
    raw: raw('update', {
      config: {
        interface: { name: 'StatPanel' },
        title: 'Status',
        status: 2,
        user: { name: 'Nick Price', observer: 0 },
      },
      data: {},
    }),
  });
}

function renderPage() {
  return render(
    <Provider store={store}>
      <Column />
    </Provider>,
  );
}

describe('the column page', () => {
  it('renders the chat in its window, the stat panel docked above it, and a docked PDA from its own messages', async () => {
    errors = [];
    const page = renderPage();
    // The chat: its tab row and its input, inside a column window (tgui layouts are mocked in tests, so its Pane is a plain box).
    expect(
      page.container.querySelector('.column-window .ChatTabs'),
    ).toBeTruthy();
    expect(
      page.container.querySelector('.column-window [data-chat-input]'),
    ).toBeTruthy();
    act(() => openStatPanel());
    // Its own protocol: the verbs it is sent reach its store through its window.
    act(() => {
      columnHost.receive('col/msg', {
        wid: 'col-stat',
        raw: raw('init_verbs', { verblist: [['IC', 'Say', 'say']] }),
      });
    });
    const groups = () =>
      Array.from(page.container.querySelectorAll('[data-column-group]'));
    expect(groups()).toHaveLength(2);
    // The stat panel (the real StatPanel interface) docks first; the chat fills the rest below.
    // Its header is titled from its first update; its body is the real interface, loaded on demand (as its chunk would be).
    expect(groups()[0].textContent).toContain('Status');
    await waitFor(
      () =>
        expect(
          groups()[0].querySelector('.EmbeddedInterface .stat-root'),
        ).toBeTruthy(),
      { timeout: 5000 },
    );
    // Its views are its own tab row, as in a native window.
    expect(groups()[0].querySelector('.stat-views')?.textContent).toContain(
      'Status',
    );
    expect(groups()[1].querySelector('.ChatTabs')).toBeTruthy();
    expect(groups()[1].className).toContain('column-group--fill');
    // A docked PDA: opened by the server, named and drawn from its own update.
    act(() => {
      columnHost.receive('col/open', { wid: 'col-7', kind: 'tgui' });
      columnHost.receive('col/msg', {
        wid: 'col-7',
        raw: raw('update', {
          config: { interface: { name: 'Pda' }, title: 'PDA', status: 2 },
          data: {
            owner: 'Nick Price',
            ownjob: 'Site Manager',
            idInserted: 1,
            idLink: 'Nick Price, Site Manager',
            useRetro: 0,
            touch_silent: 0,
            cartridge_name: '',
            stationTime: '14:07',
            app: {
              name: 'Main Menu',
              icon: 'home',
              template: 'pda_main_menu',
              has_back: 0,
              is_home: 1,
            },
            categories: [],
            apps: {},
            pai: 0,
            notifying: {},
          },
        }),
      });
    });
    await waitFor(() =>
      expect(page.container.querySelector('.EmbeddedInterface')).toBeTruthy(),
    );
    // The real PDA, drawn from its own data (its header shows the owner).
    await waitFor(
      () => expect(page.container.textContent).toContain('Nick Price'),
      { timeout: 5000 },
    );
    // Its act goes out on its own window id.
    act(() => {
      columnHost.backends.get('col-7')?.send('act/select', { app: 'notes' });
    });
    expect(sent.at(-1)).toEqual({
      type: 'col/msg',
      payload: { wid: 'col-7', type: 'act/select', payload: { app: 'notes' } },
    });
    expect(
      sent.filter((m) => m.payload?.wid === 'col-7').map((m) => m.payload.type),
    ).toContain('ready');
    // Its float and close buttons are on its header (the chat has none: it has no native window to go to yet).
    const pda = groups().find((g) => g.textContent?.includes('PDA'))!;
    expect(pda.querySelectorAll('.Button').length).toBeGreaterThanOrEqual(3);
    expect(errors).toEqual([]);
    act(() => columnHost.receive('col/close', { wid: 'col-7' }));
    expect(groups().some((g) => g.textContent?.includes('PDA'))).toBe(false);
  });
});

describe('a native window dropped on the column', () => {
  const answered = () =>
    sent.filter((m) => m.type === 'col/page' && m.payload.type === 'WM-Drop');

  it('docks at the exact list index the drop point falls at, judged in the page', async () => {
    const page = renderPage();
    act(() => openStatPanel());
    // Whatever an earlier test docked is closed but the stat panel: the column holds it and the chat.
    act(() => {
      for (const wid of [...columnHost.backends.keys()].filter(
        (w) => w !== 'col-stat',
      )) {
        columnHost.receive('col/close', { wid });
      }
    });
    // The column fills the page (its screen rect: x 1400-2000, y 0-1000 at ratio 1): the stat panel 0-400, the chat 403-1000.
    const entries = Array.from(
      page.container.querySelectorAll<HTMLElement>('[data-column-group]'),
    );
    expect(entries).toHaveLength(2);
    const place = (node: HTMLElement, top: number, height: number) => {
      node.getBoundingClientRect = () =>
        ({
          top,
          height,
          bottom: top + height,
          left: 0,
          right: 600,
          width: 600,
          x: 0,
          y: top,
        }) as DOMRect;
    };
    place(entries[0], 0, 400);
    place(entries[1], 403, 597);
    const dropAt = async (y: number) => {
      sent = [];
      columnHost.receive('col/drop-check', {
        wid: 'tgui-window-3',
        x: 1500,
        y,
      });
      await waitFor(() => expect(answered()).toHaveLength(1));
      return answered()[0].payload.payload;
    };
    // Above the stat panel's middle: first in the list.
    expect(await dropAt(100)).toEqual({ wid: 'tgui-window-3', index: 0 });
    // Below the stat panel's middle, above the chat's: between them.
    expect(await dropAt(300)).toEqual({ wid: 'tgui-window-3', index: 1 });
    // Below the chat's middle: last.
    expect(await dropAt(900)).toEqual({ wid: 'tgui-window-3', index: 2 });
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
