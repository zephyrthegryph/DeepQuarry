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

/** How much of a dragged window must stay over the main window, so it cannot be lost off to the side. */
export const GRAB_MARGIN = 96;

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
 * The area a drag may use, or null when it cannot be trusted: a measured main
 * window that does not even hold the float window's starting place (a wrong
 * origin or scale) must not pin the window to a corner of it.
 */
export function trustedArea(
  area: Rect | null,
  start: Rect | null,
): Rect | null {
  if (!area || area.w <= 0 || area.h <= 0) {
    return null;
  }
  if (!start) {
    return area;
  }
  const centre = { x: start.x + start.w / 2, y: start.y + start.h / 2 };
  return contains(area, centre) ? area : null;
}

/**
 * A dragged window rect kept reachable: it may leave the main window on any
 * side (to the top or left of it too) as long as GRAB_MARGIN of it stays over
 * the area and its top edge stays on a screen. The size is never changed.
 */
export function looseFit(
  win: Rect,
  area: Rect | null,
  margin = GRAB_MARGIN,
): Rect {
  if (!area || area.w <= 0 || area.h <= 0) {
    return win;
  }
  const m = Math.min(margin, win.w, win.h);
  return {
    x: Math.min(Math.max(win.x, area.x - win.w + m), area.x + area.w - m),
    y: Math.min(
      Math.max(win.y, Math.min(0, area.y), area.y - win.h + m),
      area.y + area.h - m,
    ),
    w: win.w,
    h: win.h,
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
