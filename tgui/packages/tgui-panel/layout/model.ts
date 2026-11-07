/**
 * The chat panel's place on the screen, as pure math: where the chat is
 * pinned, how big its share of the right-hand column is, how a drag moves the
 * floating window and when a drag ends in a pin. The server end is
 * code/content/client/floating_chat.dm, which mirrors the splitter math
 * (chat_splitter_for) and owns the winset calls; this file only measures and
 * decides.
 */

/** The chat pane is the bottom or top of the right-hand column, or its own window. */
export type ChatMode = 'bottom' | 'top' | 'float';

export const CHAT_MODES: readonly ChatMode[] = ['bottom', 'top', 'float'];

/** The pinned chat's share of the column, in percent (CHAT_SHARE_* in floating_chat.dm). */
export const SHARE_MIN = 20;
export const SHARE_MAX = 80;
export const SHARE_DEFAULT = 40;

/** A measured share only counts as the player's move when it differs from the known one by this much. */
export const SHARE_TOLERANCE = 3;

/** The floating window never gets smaller than this, in screen pixels. */
export const MIN_WINDOW_SIZE: Point = { x: 320, y: 200 };

export type Point = { x: number; y: number };

export type Rect = { x: number; y: number; w: number; h: number };

export function isMode(value: unknown): value is ChatMode {
  return CHAT_MODES.includes(value as ChatMode);
}

export function clampShare(share: number): number {
  if (!Number.isFinite(share)) {
    return SHARE_DEFAULT;
  }
  return Math.min(SHARE_MAX, Math.max(SHARE_MIN, Math.round(share)));
}

/** The share of the column the chat takes, from the chat pane's height and the column's (same unit). */
export function shareFromHeights(chat: number, column: number): number | null {
  if (!(chat > 0) || !(column > 0) || chat > column) {
    return null;
  }
  return clampShare((chat / column) * 100);
}

/** The splitter of the right-hand column (the percent its first pane takes) for a share; the chat is first at the top. */
export function splitterFor(mode: ChatMode, share: number): number {
  const clamped = clampShare(share);
  return mode === 'top' ? clamped : 100 - clamped;
}

/** Whether a measured share is the player's own move and should be reported. */
export function shareMoved(known: number, measured: number | null): boolean {
  return measured !== null && Math.abs(measured - known) >= SHARE_TOLERANCE;
}

/** The window position while dragging: where it started plus how far the mouse went (screen pixels). */
export function dragPosition(
  startWindow: Point,
  startMouse: Point,
  mouse: Point,
  pixelRatio = 1,
): Point {
  return {
    x: Math.round(startWindow.x + (mouse.x - startMouse.x) * pixelRatio),
    y: Math.round(startWindow.y + (mouse.y - startMouse.y) * pixelRatio),
  };
}

/** The window size while dragging the grip. */
export function resizeSize(
  startSize: Point,
  startMouse: Point,
  mouse: Point,
  pixelRatio = 1,
  min: Point = MIN_WINDOW_SIZE,
): Point {
  return {
    x: Math.max(
      min.x,
      Math.round(startSize.x + (mouse.x - startMouse.x) * pixelRatio),
    ),
    y: Math.max(
      min.y,
      Math.round(startSize.y + (mouse.y - startMouse.y) * pixelRatio),
    ),
  };
}

/** The window size while resizing, held to the minimum and to what is left of the area at the window's place. */
export function fitSize(
  size: Point,
  pos: Point,
  area: Rect,
  min: Point = MIN_WINDOW_SIZE,
): Point {
  if (area.w <= 0 || area.h <= 0) {
    return size;
  }
  const maxW = Math.max(1, area.x + area.w - pos.x);
  const maxH = Math.max(1, area.y + area.h - pos.y);
  return {
    x: Math.min(Math.max(size.x, Math.min(min.x, maxW)), maxW),
    y: Math.min(Math.max(size.y, Math.min(min.y, maxH)), maxH),
  };
}

/** Whether a point lies in a rect. */
export function contains(rect: Rect, point: Point): boolean {
  return (
    point.x >= rect.x &&
    point.x <= rect.x + rect.w &&
    point.y >= rect.y &&
    point.y <= rect.y + rect.h
  );
}

/**
 * A window rect held fully inside the area: the size is cut to the area first
 * (never under the minimum unless the area is smaller), then the place. The
 * area's own edges are the limits, so the window reaches every side of it.
 */
export function fitRect(
  win: Rect,
  area: Rect | null,
  min: Point = MIN_WINDOW_SIZE,
): Rect {
  if (!area || area.w <= 0 || area.h <= 0) {
    return win;
  }
  const w = Math.min(Math.max(win.w, Math.min(min.x, area.w)), area.w);
  const h = Math.min(Math.max(win.h, Math.min(min.y, area.h)), area.h);
  return {
    x: Math.min(Math.max(win.x, area.x), area.x + area.w - w),
    y: Math.min(Math.max(win.y, area.y), area.y + area.h - h),
    w,
    h,
  };
}

/** How near (CSS pixels, scaled by the pixel ratio) a window edge gets to a main-window edge before it snaps flush to it. */
export const SNAP_DISTANCE = 16;

/**
 * A window rect pulled flush to the area's edges when one is within `distance`
 * (physical pixels): each axis snaps on its own, so a rect near a corner
 * snaps on both. Snapping never leaves the area, so containment holds.
 */
export function snapRect(
  win: Rect,
  area: Rect | null,
  distance = SNAP_DISTANCE,
): Rect {
  if (!area || area.w <= 0 || area.h <= 0 || distance <= 0) {
    return win;
  }
  const snapAxis = (
    pos: number,
    size: number,
    from: number,
    extent: number,
  ) => {
    const low = Math.abs(pos - from);
    const high = Math.abs(pos + size - (from + extent));
    if (low <= distance && low <= high) {
      return from;
    }
    if (high <= distance) {
      return from + extent - size;
    }
    return pos;
  };
  return {
    ...win,
    x: snapAxis(win.x, win.w, area.x, area.w),
    y: snapAxis(win.y, win.h, area.y, area.h),
  };
}

/** The chat's share of the column when dropped as a window of height `winHeight` (same unit as `columnHeight`). */
export function dockShare(winHeight: number, columnHeight: number): number {
  return shareFromHeights(winHeight, columnHeight) ?? SHARE_DEFAULT;
}

/** The main window's split between the map and the right-hand column is kept in this range (percent the map takes). */
export const MAP_SPLIT_MIN = 10;
export const MAP_SPLIT_MAX = 90;

/** What BYOND reports for the main window (winget), parsed. */
export type MainReport = {
  pos: Point | null;
  outerSize: Point | null;
  size: Point | null;
  innerSize: Point | null;
  maximized: boolean;
};

/**
 * The main window's outer rect and client area in screen pixels, plus the part
 * of it that is on the screen. `screen` is the monitor's work area in screen
 * pixels.
 *
 * A maximized window reports the pos and size it has when NOT maximized (the
 * skin's 640x440 centred on the screen), only outer-size and inner-size are
 * live. Taking that pos as the origin put the "main window" at the middle of
 * the screen, so the float window could not go above or left of it. A
 * maximized window is as large as its outer size and centred on the work
 * area (its borders hang over the edges evenly), so its origin follows from
 * those.
 */
export function mainRects(
  report: MainReport,
  screen: Rect | null,
): { outer: Rect; client: Rect; visible: Rect } | null {
  const outerSize = report.outerSize ?? report.size;
  if (!outerSize || outerSize.x <= 0 || outerSize.y <= 0) {
    return null;
  }
  let origin: Point;
  if (report.maximized) {
    const work = screen ?? { x: 0, y: 0, w: outerSize.x, h: outerSize.y };
    origin = {
      x: Math.round(work.x + (work.w - outerSize.x) / 2),
      y: Math.round(work.y + (work.h - outerSize.y) / 2),
    };
  } else if (report.pos) {
    origin = report.pos;
  } else {
    return null;
  }
  const outer = { x: origin.x, y: origin.y, w: outerSize.x, h: outerSize.y };
  const clientSize =
    report.innerSize ??
    (report.maximized
      ? { x: screen?.w ?? outerSize.x, y: screen?.h ?? outerSize.y }
      : (report.size ?? outerSize));
  const client = clientRect(outer, clientSize);
  const visible = report.maximized && screen ? intersect(outer, screen) : outer;
  return { outer, client, visible };
}

/** The overlap of two rects (zero-sized when they do not meet). */
export function intersect(a: Rect, b: Rect): Rect {
  const x = Math.max(a.x, b.x);
  const y = Math.max(a.y, b.y);
  return {
    x,
    y,
    w: Math.max(0, Math.min(a.x + a.w, b.x + b.w) - x),
    h: Math.max(0, Math.min(a.y + a.h, b.y + b.h) - y),
  };
}

/**
 * The main window's client area in screen pixels from its outer rect and the
 * client size (borders are even on the sides and the bottom; the title bar and top border are what is left above).
 */
export function clientRect(outer: Rect, client: Point): Rect {
  const border = Math.max(0, (outer.w - client.x) / 2);
  const top = Math.max(0, outer.h - client.y - border);
  return {
    x: outer.x + border,
    y: outer.y + top,
    w: Math.min(client.x, outer.w),
    h: Math.min(client.y, outer.h),
  };
}

/** The right-hand column in screen pixels: as wide and tall as measured, against the right edge of the client area. */
export function columnRect(client: Rect, column: Point): Rect {
  const w = Math.min(Math.max(column.x, 0), client.w);
  const h = Math.min(Math.max(column.y, 0), client.h);
  return { x: client.x + client.w - w, y: client.y, w, h };
}

/** Where dropping with the pointer at `pointer` docks: over the column, the upper half is top right, the lower half bottom right. */
export function dockTarget(
  pointer: Point,
  column: Rect | null,
): 'top' | 'bottom' | null {
  if (!column || column.w <= 0 || column.h <= 0 || !contains(column, pointer)) {
    return null;
  }
  return pointer.y < column.y + column.h / 2 ? 'top' : 'bottom';
}

/** How far (screen pixels) a docked chat is dragged before it pops out into a window. */
export const POP_OUT_DISTANCE = 14;

/** Whether a drag from `start` to `now` has gone far enough to pop out. */
export function poppedOut(
  start: Point,
  now: Point,
  distance = POP_OUT_DISTANCE,
): boolean {
  return Math.hypot(now.x - start.x, now.y - start.y) >= distance;
}

/** The window place that puts the pointer on the middle of the window's top strip. */
export function windowUnderPointer(pointer: Point, size: Point): Point {
  return {
    x: Math.round(pointer.x - size.x / 2),
    y: Math.round(pointer.y - 16),
  };
}
