/**
 * The window dock's host in the stat panel (doc/rewrite/proposals/window_system.md):
 * holds the layout (windowDock.ts), talks to the server (wm/* in, WM-* out),
 * and places each shown docked tgui window over its placeholder in the dock
 * area. The windows are their own BYOND windows; this page only moves, sizes,
 * shows and hides them.
 */
import { mainBounds } from '../layout/geometry';
import { columnRect, type Point } from '../layout/model';
import {
  type DockAction,
  type DockState,
  type DockWindow,
  dockReduce,
  emptyDock,
  hiddenIds,
  parseSaved,
  serializeSaved,
  shownIds,
} from './windowDock';

const SAVE_DELAY_MS = 1000;
const ORIGIN_POLL_MS = 1000;

const isPoint = (value: unknown): value is Point =>
  !!value &&
  typeof (value as Point).x === 'number' &&
  typeof (value as Point).y === 'number';

const asEntry = (value: any): DockWindow | null =>
  value && typeof value.id === 'string'
    ? {
        id: value.id,
        iface: String(value.interface ?? value.id),
        title: String(value.title ?? value.interface ?? ''),
      }
    : null;

/**
 * The list index a window dropped on the panel goes to: `y` is the drop's y
 * in the panel page (CSS px), against the entries' middles. Undefined when the
 * drop gave no point (a dock button, a reload).
 */
function dropIndexAt(y: number): number {
  const entries = Array.from(
    document.querySelectorAll<HTMLElement>('[data-dock-group]'),
  );
  const index = entries.findIndex((node) => {
    const rect = node.getBoundingClientRect();
    return y < rect.top + rect.height / 2;
  });
  return index < 0 ? entries.length : index;
}

/** Where the stat panel page's top left is on the screen, in physical pixels. */
async function pageOrigin(): Promise<Point | null> {
  try {
    const got = await Byond.winget('statwindow', 'screen-pos');
    if (isPoint(got)) {
      return got;
    }
  } catch {
    // Older clients have no screen-pos: work it out from the column.
  }
  const main = await mainBounds();
  if (!main) {
    return null;
  }
  try {
    const got = await Byond.winget('rpane.rpanewindow', ['size', 'left']);
    if (!isPoint(got?.size)) {
      return null;
    }
    const column = columnRect(main.client, got.size);
    const ratio = window.devicePixelRatio || 1;
    const chatOnTop = got.left === 'outputwindow';
    return {
      x: column.x,
      y: chatOnTop
        ? column.y + column.h - Math.round(window.innerHeight * ratio)
        : column.y,
    };
  } catch {
    return null;
  }
}

/**
 * Tells the page which side of it the chat is on (`html[data-chat-side]`), so
 * the panel leaves out its own frame edge there: the chat's frame is the one
 * line between them, the same 3px gap as every other edge, not two frames.
 */
async function markChatSide(): Promise<void> {
  try {
    const got = await Byond.winget('rpane.rpanewindow', 'left');
    const side = got === 'outputwindow' ? 'top' : 'bottom';
    if (document.documentElement.dataset.chatSide !== side) {
      document.documentElement.dataset.chatSide = side;
      console.log('statpanel: chat side', side);
    }
  } catch {
    // An older client: both frames stay.
  }
}

export class DockHost {
  state: DockState = emptyDock();
  private version = 0;
  private listeners = new Set<() => void>();
  private bodies = new Map<string, HTMLElement>();
  private area: HTMLElement | null = null;
  private placed = new Map<string, string>();
  private lastHidden = '';
  private lastSaved = '';
  private saveTimer: ReturnType<typeof setTimeout> | undefined;
  private origin: Point | null = null;
  /** While a header is dragged every window hides, so the drop targets show. */
  dragging = false;
  private frame = 0;

  constructor() {
    window.addEventListener('resize', () => {
      this.refreshOrigin();
      markChatSide();
    });
    markChatSide();
    setInterval(() => {
      if (this.state.groups.length) {
        this.refreshOrigin();
      }
    }, ORIGIN_POLL_MS);
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getVersion = () => this.version;

  dispatch = (action: DockAction) => {
    const next = dockReduce(this.state, action);
    if (next === this.state) {
      return;
    }
    this.state = next;
    this.version++;
    for (const listener of this.listeners) listener();
    this.afterChange();
  };

  /** Server messages; returns whether it was one of the dock's. */
  receive(type: string, payload: any): boolean {
    switch (type) {
      case 'wm/init': {
        this.lastSaved =
          typeof payload?.saved === 'string' ? payload.saved : '';
        this.dispatch({ type: 'load', saved: parseSaved(payload?.saved) });
        for (const value of payload?.windows ?? []) {
          const entry = asEntry(value);
          if (entry) this.dispatch({ type: 'open', window: entry });
        }
        return true;
      }
      case 'wm/open': {
        const entry = asEntry(payload);
        if (entry) {
          const at = this.pageY(payload?.at);
          if (at !== null) {
            entry.at = dropIndexAt(at);
          }
          this.placed.delete(entry.id);
          this.dispatch({ type: 'open', window: entry });
          this.refreshOrigin();
        }
        return true;
      }
      case 'wm/close':
        if (typeof payload?.id === 'string') {
          // The window is no longer ours to place (it floats or was suspended).
          this.placed.delete(payload.id);
          this.dispatch({ type: 'close', id: payload.id });
        }
        return true;
    }
    return false;
  }

  /** The panel is up: ask for the saved layout and the windows docked now. */
  ready() {
    Byond.sendMessage('WM-Ready');
  }

  /** Floats window `id`; with `at` (screen pixels) it opens under that point, as a popped-out chat does. */
  float(id: string, at?: Point | null) {
    this.placed.delete(id);
    this.dispatch({ type: 'float', id });
    Byond.sendMessage('WM-Float', at ? { id, at } : { id });
  }

  /** Floats every window of a group: the shown one under `at`, the others where they last floated. */
  floatGroup(group: string, at: Point | null) {
    const found = this.state.groups.find((g) => g.id === group);
    if (!found) {
      return;
    }
    for (const id of found.windows) {
      this.float(id, id === found.active ? at : null);
    }
  }

  /** A point of this page (CSS px) on the screen (physical px), or null before the page's place is known. */
  screenPoint(x: number, y: number): Point | null {
    if (!this.origin) {
      return null;
    }
    const ratio = window.devicePixelRatio || 1;
    return {
      x: Math.round(this.origin.x + x * ratio),
      y: Math.round(this.origin.y + y * ratio),
    };
  }

  /** A screen point's (physical px, `{x, y}`) y in this page (CSS px), or null. */
  private pageY(at: unknown): number | null {
    if (!this.origin || !isPoint(at)) {
      return null;
    }
    return (at.y - this.origin.y) / (window.devicePixelRatio || 1);
  }

  /** The dock area's node (the list drags measure it). */
  get areaNode(): HTMLElement | null {
    return this.area;
  }

  close(id: string) {
    Byond.sendMessage('WM-Close', { id });
  }

  setArea(node: HTMLElement | null) {
    this.area = node;
    this.schedule();
  }

  setBody(id: string, node: HTMLElement | null) {
    if (node) {
      this.bodies.set(id, node);
    } else {
      this.bodies.delete(id);
    }
    this.schedule();
  }

  setDragging(dragging: boolean) {
    this.dragging = dragging;
    this.version++;
    for (const listener of this.listeners) listener();
    this.schedule();
  }

  private afterChange() {
    const hidden = hiddenIds(this.state);
    const key = hidden.join(',');
    if (key !== this.lastHidden) {
      this.lastHidden = key;
      Byond.sendMessage('WM-View', { hidden });
    }
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      const text = serializeSaved(this.state.saved);
      if (text !== this.lastSaved) {
        this.lastSaved = text;
        Byond.sendMessage('WM-Save', { layout: text });
      }
    }, SAVE_DELAY_MS);
    this.schedule();
  }

  private async refreshOrigin() {
    const origin = await pageOrigin();
    if (
      origin &&
      (!this.origin || origin.x !== this.origin.x || origin.y !== this.origin.y)
    ) {
      this.origin = origin;
    }
    this.schedule();
  }

  /** Re-places on the next frame (layout, scroll and resize all come here). */
  schedule = () => {
    if (!this.frame) {
      this.frame = requestAnimationFrame(() => {
        this.frame = 0;
        this.place();
      });
    }
  };

  private place() {
    const shown = this.dragging ? [] : shownIds(this.state);
    const ratio = window.devicePixelRatio || 1;
    const clip = this.area?.getBoundingClientRect();
    for (const id of Object.keys(this.state.windows)) {
      const body = this.bodies.get(id);
      let params: Record<string, string | number | boolean> | null = null;
      if (shown.includes(id) && body && clip && this.origin) {
        const rect = body.getBoundingClientRect();
        const top = Math.max(rect.top, clip.top);
        const bottom = Math.min(rect.bottom, clip.bottom);
        if (bottom - top >= 8 && rect.width >= 8) {
          const x = Math.round(this.origin.x + rect.left * ratio);
          const y = Math.round(this.origin.y + top * ratio);
          const w = Math.round(rect.width * ratio);
          const h = Math.round((bottom - top) * ratio);
          params = {
            pos: `${x},${y}`,
            size: `${w}x${h}`,
            alpha: 255,
            'is-visible': true,
          };
        }
      }
      const next = params ? JSON.stringify(params) : 'hidden';
      if (this.placed.get(id) === next) {
        continue;
      }
      this.placed.set(id, next);
      Byond.winset(id, params ?? { 'is-visible': false });
    }
  }
}

export const dockHost = new DockHost();
