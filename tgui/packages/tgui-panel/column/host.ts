/**
 * The right-hand column's window manager (doc/rewrite/proposals/
 * window_system.md section 12). The column is this one page; the chat, the
 * stat panel's views and every docked tgui interface are windows in it, laid
 * out by one model (model.ts) and drawn by one component (Column.tsx).
 *
 * Server windows in the column (the stat panel, docked interfaces) are
 * "column parts": the server opens one with `col/open {wid}`, sends it
 * messages as `col/msg {wid, raw}` and closes it with `col/close {wid}`; the
 * page answers for it with `col/msg {wid, type, payload}`.
 */
import {
  applyEmbeddedMessage,
  createEmbeddedBackend,
  type EmbeddedBackend,
} from 'tgui/embedded';
import { configAtom } from 'tgui/events/store';
import { mainBounds, measureColumn } from '../layout/geometry';
import {
  createStatHost,
  STAT_WINDOW_ID,
  type StatHost,
} from '../statpanel/host';
import type { PanelView } from '../statpanel/layout';
import { viewsOf } from '../statpanel/store';
import {
  type DockAction,
  type DockState,
  type DockWindow,
  dockReduce,
  emptyDock,
  parseSaved,
  serializeSaved,
} from './model';

/** The chat's window id in the column. */
export const CHAT_WINDOW = 'chat';
/** A stat panel view's window id in the column. */
export const statWindowId = (view: string) => `stat:${view}`;
/** The group the stat views stack in by default. */
const STAT_GROUP = 'stat';
const SAVE_DELAY_MS = 1000;

/** Sends a message for one of the column's server windows. */
export function sendFor(
  wid: string,
  type: string,
  payload: Record<string, unknown> = {},
) {
  Byond.sendMessage('col/msg', { wid, type, payload });
}

/** A raw tgui message (TGUI_CREATE_MESSAGE's format) as {type, payload}. */
export function decodeRaw(raw: unknown): { type: string; payload: any } | null {
  if (typeof raw !== 'string') return null;
  try {
    const message = JSON.parse(decodeURIComponent(raw));
    return typeof message?.type === 'string' ? message : null;
  } catch {
    return null;
  }
}

export class ColumnHost {
  state: DockState = emptyDock();
  /** Docked tgui interfaces by window id: their own stores and channels. */
  backends = new Map<string, EmbeddedBackend>();
  stat: StatHost;
  private version = 0;
  private listeners = new Set<() => void>();
  private saveTimer: ReturnType<typeof setTimeout> | undefined;
  private lastSaved = '';
  /** What each docked interface was last told about being on screen (wm/view). */
  private viewHidden = new Map<string, boolean>();
  private statViews = '';

  constructor() {
    this.stat = createStatHost((type, payload) =>
      sendFor(STAT_WINDOW_ID, type, payload),
    );
    this.stat.store.subscribe(() => this.syncStatViews());
    this.dispatch({
      type: 'open',
      window: { id: CHAT_WINDOW, iface: 'Chat', title: 'Chat', kind: 'chat' },
    });
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getVersion = () => this.version;

  private changed() {
    this.version++;
    for (const listener of this.listeners) listener();
  }

  dispatch = (action: DockAction) => {
    const next = dockReduce(this.state, action);
    if (next === this.state) return;
    this.state = next;
    this.changed();
    this.scheduleSave();
    this.reportViews();
  };

  /**
   * Tells the server which docked interfaces are off screen (their entry
   * collapsed, or a background tab of a stack): those get no data pushes
   * until shown again, when they get one fresh update (dock_hide()).
   */
  private reportViews() {
    for (const group of this.state.groups) {
      for (const id of group.windows) {
        if (this.state.windows[id]?.kind !== 'tgui') continue;
        const hidden = group.collapsed || id !== group.active;
        if (this.viewHidden.get(id) === hidden) continue;
        this.viewHidden.set(id, hidden);
        sendFor(id, 'wm/view', { hidden });
      }
    }
    for (const id of this.viewHidden.keys()) {
      if (!this.state.windows[id]) this.viewHidden.delete(id);
    }
  }

  /** The stat panel's views as stacked column windows, kept in step with the panel's own list. */
  private syncStatViews() {
    const views = viewsOf(this.stat.store.state) as PanelView[];
    const key = views.join(',');
    if (key !== this.statViews) {
      this.statViews = key;
      for (const id of Object.keys(this.state.windows)) {
        const win = this.state.windows[id];
        if (
          win.kind === 'stat' &&
          !views.includes(win.iface.slice(5) as PanelView)
        ) {
          this.dispatch({ type: 'close', id });
        }
      }
      for (const view of views) {
        const id = statWindowId(view);
        if (this.state.windows[id]) continue;
        const stack = this.state.groups.find((group) =>
          group.windows.some((w) => this.state.windows[w]?.kind === 'stat'),
        );
        // Taken before opening: every open re-snapshots `saved`.
        const placed = !!this.state.saved[`Stat:${view}`];
        this.dispatch({
          type: 'open',
          window: {
            id,
            iface: `Stat:${view}`,
            title: view,
            kind: 'stat',
            // With no saved place, the stat panel starts above the chat, as the column always had it.
            at: !placed && !stack ? 0 : undefined,
          },
        });
        // A view the saved layout does not place joins the other views' stack.
        const at = this.state.groups.findIndex((g) => g.windows.includes(id));
        const own = this.state.groups[at];
        if (
          stack &&
          own &&
          own.id !== stack.id &&
          own.windows.length === 1 &&
          !placed
        ) {
          this.dispatch({ type: 'joinGroup', group: own.id, into: stack.id });
        }
      }
    }
    // The stat panel shows one view at a time: its stack's active tab follows the panel's view.
    const shown = statWindowId(this.stat.store.state.view);
    const group = this.state.groups.find((g) => g.windows.includes(shown));
    if (group && group.active !== shown && group.windows.length > 1) {
      this.dispatch({ type: 'activate', id: shown });
    }
  }

  /** A window's stack tab was chosen: a stat view also becomes the panel's view. */
  activate(id: string) {
    const win = this.state.windows[id];
    if (win?.kind === 'stat') {
      this.stat.store.setView(win.iface.slice(5) as PanelView);
    }
    this.dispatch({ type: 'activate', id });
  }

  /** Server messages for the column; returns whether it was one. */
  receive(type: string, payload: any): boolean {
    switch (type) {
      case 'col/open':
        this.open(payload);
        return true;
      case 'col/msg':
        this.message(payload);
        return true;
      case 'col/close':
        if (typeof payload?.wid === 'string') this.closed(payload.wid);
        return true;
      case 'col/drop-check':
        this.dropCheck(payload);
        return true;
      case 'col/init':
        this.lastSaved =
          typeof payload?.saved === 'string' ? payload.saved : '';
        this.dispatch({ type: 'load', saved: parseSaved(payload?.saved) });
        return true;
    }
    return false;
  }

  private open(payload: any) {
    const wid = payload?.wid;
    if (typeof wid !== 'string') return;
    if (wid === STAT_WINDOW_ID) {
      this.stat.ready();
      this.syncStatViews();
      return;
    }
    const backend = createEmbeddedBackend(wid, (type, message) =>
      sendFor(wid, type, message),
    );
    this.backends.set(wid, backend);
    const at = typeof payload?.at === 'number' ? payload.at : undefined;
    // Its interface and title come with its first update; until then it is placed by its id.
    this.dispatch({
      type: 'open',
      window: { id: wid, iface: wid, title: '', kind: 'tgui', at },
    });
    sendFor(wid, 'ready');
  }

  private message(payload: any) {
    const wid = payload?.wid;
    const message = decodeRaw(payload?.raw);
    if (typeof wid !== 'string' || !message) return;
    if (wid === STAT_WINDOW_ID) {
      this.stat.receive(message.type, message.payload);
      return;
    }
    const backend = this.backends.get(wid);
    if (!backend) return;
    if (message.type === 'ping') {
      sendFor(wid, 'ping/reply', message.payload ?? {});
      return;
    }
    applyEmbeddedMessage(backend, message.type, message.payload);
    if (message.type === 'update') {
      const config = backend.store.get(configAtom);
      const iface = config?.interface?.name;
      const title = config?.title || iface || '';
      const win = this.state.windows[wid];
      if (win && iface && (win.iface !== iface || win.title !== title)) {
        this.retitle(wid, iface, title);
      }
    }
  }

  /** A docked window's interface became known: it takes its name (for the saved layout) and title. */
  private retitle(wid: string, iface: string, title: string) {
    const win = this.state.windows[wid];
    if (!win) return;
    if (win.iface !== iface) {
      // Placed again under its interface's saved place, unless a drop put it somewhere.
      const placed = this.state.saved[iface];
      this.dispatch({ type: 'close', id: wid });
      this.dispatch({
        type: 'open',
        window: {
          id: wid,
          iface,
          title,
          kind: 'tgui',
          at: win.at ?? (placed ? undefined : this.state.groups.length - 1),
        },
      });
    } else {
      this.dispatch({ type: 'title', id: wid, title });
    }
  }

  private closed(wid: string) {
    this.backends.delete(wid);
    this.dispatch({ type: 'close', id: wid });
  }

  /** Closes a docked interface (its close button). */
  close(wid: string) {
    sendFor(wid, 'close');
  }

  /** Floats a docked interface out into a native window, under a screen point when a drag gave one. */
  float(wid: string, at?: { x: number; y: number } | null) {
    sendFor(wid, 'wm/float', at ? { at } : {});
  }

  /**
   * A native window was dropped at screen point (x, y): when that is over
   * this page, answer with where in the list it falls, and the server docks
   * it there. The page's screen place is its own client area's.
   */
  private async dropCheck(payload: any) {
    // The column's screen rect: the same measurement the chat's own pin to the column uses (layout/geometry.ts).
    const column = await measureColumn(await mainBounds());
    const ratio = window.devicePixelRatio || 1;
    const px = Number(payload?.x);
    const py = Number(payload?.y);
    const inside =
      !!column &&
      px >= column.x &&
      py >= column.y &&
      px <= column.x + column.w &&
      py <= column.y + column.h;
    const y = column ? (py - column.y) / ratio : Number.NaN;
    sendFor(STAT_WINDOW_ID, 'WM-Log', {
      drop: inside ? 'column' : 'outside',
      point: [px, py],
      column,
      ratio,
    });
    if (!inside) return;
    const entries = Array.from(
      document.querySelectorAll<HTMLElement>('[data-column-group]'),
    );
    let index = entries.findIndex((node) => {
      const rect = node.getBoundingClientRect();
      return y < rect.top + rect.height / 2;
    });
    if (index < 0) index = entries.length;
    sendFor(STAT_WINDOW_ID, 'WM-Drop', { wid: payload?.wid, index });
  }

  private scheduleSave() {
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      const text = serializeSaved(this.state.saved);
      if (text !== this.lastSaved) {
        this.lastSaved = text;
        sendFor(STAT_WINDOW_ID, 'WM-Save', { layout: text });
      }
    }, SAVE_DELAY_MS);
  }

  /** The window entry of `id`, if the column has it. */
  windowOf(id: string): DockWindow | undefined {
    return this.state.windows[id];
  }
}

export const columnHost = new ColumnHost();
