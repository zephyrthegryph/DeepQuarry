/**
 * The right-hand column's window manager (doc/rewrite/proposals/
 * window_system.md section 12). The column is this one page; the chat and
 * every docked tgui interface (the stat panel among them) are windows in it, laid
 * out by one model (model.ts) and drawn by one component (Column.tsx).
 *
 * Server windows in the column (the stat panel, docked interfaces) are
 * "column parts": the server opens one with `col/open {wid}`, sends it
 * messages as `col/msg {wid, type, payload}` and closes it with `col/close {wid}`; the
 * page answers for it with `col/msg {wid, type, payload}`.
 */
import {
  applyEmbeddedMessage,
  createEmbeddedBackend,
  type EmbeddedBackend,
} from 'tgui/embedded';
import { configAtom } from 'tgui/events/store';
import { prepareRequestedInterface } from 'tgui/interfacePreparation';
import { mainBounds, measureColumn } from '../layout/geometry';
import { rectContains } from '../layout/model';
import {
  type DockAction,
  type DockState,
  type DockWindow,
  dockReduce,
  emptyDock,
  parseSaved,
  serializeSaved,
} from './model';

const SAVE_DELAY_MS = 1000;
/** The chat's stand-in until its window arrives (the page's own chat, drawn where the Chat window will be). */
export const CHAT_PENDING = 'chat-pending';
const CHAT_INTERFACE = 'Chat';

/** Sends a message of the column page itself (its layout saves, drop answers, logs): the server's window dock (window_dock.dm). */
export function sendPage(type: string, payload: Record<string, unknown> = {}) {
  Byond.sendMessage('col/page', { type, payload });
}

/** Sends a message for one of the column's server windows. */
export function sendFor(
  wid: string,
  type: string,
  payload: Record<string, unknown> = {},
) {
  Byond.sendMessage('col/msg', { wid, type, payload });
}

export class ColumnHost {
  state: DockState = emptyDock();
  /** Docked tgui interfaces by window id: their own stores and channels. */
  backends = new Map<string, EmbeddedBackend>();
  private version = 0;
  private listeners = new Set<() => void>();
  private saveTimer: ReturnType<typeof setTimeout> | undefined;
  private lastSaved = '';
  /** What each docked interface was last told about being on screen (wm/view). */
  private viewHidden = new Map<string, boolean>();
  /** The list index a window was opened at (a drop put it there), until its interface is named and it is placed again at the same index. */
  private openedAt = new Map<string, number>();

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
        const hidden = this.collapsed(group) || id !== group.active;
        if (this.viewHidden.get(id) === hidden) continue;
        this.viewHidden.set(id, hidden);
        sendFor(id, 'wm/view', { hidden });
      }
    }
    for (const id of this.viewHidden.keys()) {
      if (!this.state.windows[id]) this.viewHidden.delete(id);
    }
  }

  /** A window's stack tab was chosen. */
  activate(id: string) {
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
        this.awaitChat();
        return true;
    }
    return false;
  }

  private open(payload: any) {
    const wid = payload?.wid;
    if (typeof wid !== 'string') return;
    const backend = createEmbeddedBackend(wid, (type, message) =>
      sendFor(wid, type, message),
    );
    this.backends.set(wid, backend);
    const at = typeof payload?.at === 'number' ? payload.at : undefined;
    if (at !== undefined) this.openedAt.set(wid, at);
    // Its interface and title come with its first update; until then it has no interface, so the saved layout does not hear of it.
    this.dispatch({
      type: 'open',
      window: { id: wid, iface: '', title: '', kind: 'tgui', at },
    });
    sendFor(wid, 'ready');
  }

  private message(payload: any) {
    const wid = payload?.wid;
    // One envelope {wid, type, payload}, decoded once with the page's own message (column_part.dm wrap_message()).
    const message =
      typeof payload?.type === 'string'
        ? { type: payload.type as string, payload: payload.payload }
        : null;
    if (typeof wid !== 'string' || !message) return;
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

  /**
   * Until the server's Chat window arrives, the chat docks at once as a
   * stand-in (the page's own chat, the same component and store the Chat
   * window draws), so the column never shows a blank moment at login; the
   * Chat window takes the stand-in's place. A chat the player floated has
   * no stand-in.
   */
  private awaitChat() {
    const docked = this.state.saved[CHAT_INTERFACE]?.dock ?? true;
    const open = Object.values(this.state.windows).some(
      (win) => win.iface === CHAT_INTERFACE,
    );
    if (!docked || open) return;
    // Its chunk loads now, so the real window draws the moment it is named.
    prepareRequestedInterface(CHAT_INTERFACE)?.catch(() => undefined);
    this.dispatch({
      type: 'open',
      window: {
        id: CHAT_PENDING,
        iface: CHAT_INTERFACE,
        title: 'Chat',
        kind: 'pending',
      },
    });
  }

  /** The Chat window `wid` takes the stand-in's place once its interface can draw. */
  private replacePending(wid: string, title: string) {
    const swap = () => {
      // Its list index once the window's own provisional entry is gone.
      const groups = this.state.groups.filter((g) => !g.windows.includes(wid));
      const at = groups.findIndex((g) => g.windows.includes(CHAT_PENDING));
      if (at < 0 || !this.state.windows[wid]) return;
      this.dispatch({ type: 'close', id: CHAT_PENDING });
      this.dispatch({ type: 'close', id: wid });
      this.dispatch({
        type: 'open',
        window: { id: wid, iface: CHAT_INTERFACE, title, kind: 'tgui', at },
      });
    };
    const loading = prepareRequestedInterface(CHAT_INTERFACE);
    if (loading) loading.then(swap, swap);
    else swap();
  }

  /** A docked window's interface became known: it takes its name (for the saved layout) and title. */
  private retitle(wid: string, iface: string, title: string) {
    const win = this.state.windows[wid];
    if (!win) return;
    const openedAt = this.openedAt.get(wid);
    this.openedAt.delete(wid);
    if (
      win.iface !== iface &&
      iface === CHAT_INTERFACE &&
      this.state.windows[CHAT_PENDING]
    ) {
      this.replacePending(wid, title);
      return;
    }
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
          at: openedAt ?? (placed ? undefined : this.unplacedIndex(wid)),
        },
      });
    } else {
      this.dispatch({ type: 'title', id: wid, title });
    }
  }

  /**
   * Where a window with no saved place goes: above the chat, which fills the
   * rest of the column at its foot; with no chat docked, last.
   */
  private unplacedIndex(wid: string): number {
    const { groups, windows } = this.state;
    const chat = groups.findIndex((group) =>
      group.windows.some((id) => id !== wid && windows[id]?.iface === 'Chat'),
    );
    const others = groups.filter((group) => !group.windows.includes(wid));
    return chat < 0 ? others.length : others.indexOf(groups[chat]);
  }

  private closed(wid: string) {
    this.backends.delete(wid);
    this.openedAt.delete(wid);
    this.dispatch({ type: 'close', id: wid });
  }

  /** The window config the server sent a docked interface (its floatable, collapsible and closable words). */
  private windowConfig(wid: string) {
    return this.backends.get(wid)?.store.get(configAtom)?.window;
  }

  /** Whether an entry can fold to its header: never one holding a window the server says cannot (the stat panel). */
  mayCollapse(group: { windows: string[] }): boolean {
    return !group.windows.some(
      (id) => this.windowConfig(id)?.collapsible === false,
    );
  }

  /** Whether an entry is folded now (a saved fold of an always-docked window does not count). */
  collapsed(group: { collapsed: boolean; windows: string[] }): boolean {
    return group.collapsed && this.mayCollapse(group);
  }

  /** Whether a window's header offers float and close, and a drag out floats it: the server says so (closable) and it may leave. */
  hasWindowButtons(wid: string): boolean {
    return this.windowConfig(wid)?.closable !== false && this.mayLeave(wid);
  }

  /**
   * Whether docked window `wid` may leave the column (float or close): a
   * tgui window whose interface floats (the stat panel never does), and
   * never the column's last window (the column is never empty). The server
   * holds the same rule (window_dock.dm may_leave()).
   */
  mayLeave(wid: string): boolean {
    const win = this.state.windows[wid];
    if (win?.kind !== 'tgui') return false;
    const floatable = this.backends.get(wid)?.store.get(configAtom)
      ?.window?.floatable;
    if (floatable === false) return false;
    const docked = Object.values(this.state.windows).filter(
      (w) => w.kind === 'tgui',
    ).length;
    return docked > 1;
  }

  /** Closes a docked interface (its close button). */
  close(wid: string) {
    if (!this.mayLeave(wid)) return;
    sendFor(wid, 'close');
  }

  /** Floats a docked interface out into a native window, under a screen point when a drag gave one. */
  float(wid: string, at?: { x: number; y: number } | null) {
    // A drag can end after its window closed (the server closed it, the page reloaded): nothing is left to float. Nor does a window
    // the column keeps (the stat panel, the last window).
    if (!this.mayLeave(wid)) return;
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
    const inside = !!column && rectContains(column, px, py);
    const y = column ? (py - column.y) / ratio : Number.NaN;
    if (this.profiling()) {
      sendPage('WM-Log', {
        drop: inside ? 'column' : 'outside',
        point: [px, py],
        column,
        ratio,
      });
    }
    if (!inside) return;
    const entries = Array.from(
      document.querySelectorAll<HTMLElement>('[data-column-group]'),
    );
    let index = entries.findIndex((node) => {
      const rect = node.getBoundingClientRect();
      return y < rect.top + rect.height / 2;
    });
    if (index < 0) index = entries.length;
    sendPage('WM-Drop', { wid: payload?.wid, index });
  }

  private scheduleSave() {
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      const text = serializeSaved(this.state.saved);
      if (text !== this.lastSaved) {
        this.lastSaved = text;
        sendPage('WM-Save', { layout: text });
      }
    }, SAVE_DELAY_MS);
  }

  /** Whether the server runs this client in profiling mode (any docked interface's config says so): diagnostics are sent only then. */
  private profiling(): boolean {
    for (const backend of this.backends.values()) {
      if (backend.store.get(configAtom)?.client?.profiling) return true;
    }
    return false;
  }

  /** The window entry of `id`, if the column has it. */
  windowOf(id: string): DockWindow | undefined {
    return this.state.windows[id];
  }
}

export const columnHost = new ColumnHost();
