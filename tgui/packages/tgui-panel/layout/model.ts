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

/** A drag that ends with the window's right edge this close to the column's right edge pins the chat. */
export const SNAP_THRESHOLD = 72;

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
    x: Math.max(min.x, Math.round(startSize.x + (mouse.x - startMouse.x) * pixelRatio)),
    y: Math.max(min.y, Math.round(startSize.y + (mouse.y - startMouse.y) * pixelRatio)),
  };
}

/**
 * Where a dropped window pins: near the right edge of the area (the main
 * window), the top half pins top right and the bottom half bottom right.
 * Null when the window is too far from the edge, or overlaps the area too little.
 */
export function snapTarget(
  win: Rect,
  area: Rect,
  threshold = SNAP_THRESHOLD,
): 'top' | 'bottom' | null {
  if (area.w <= 0 || area.h <= 0) {
    return null;
  }
  const gap = Math.abs(win.x + win.w - (area.x + area.w));
  if (gap > threshold) {
    return null;
  }
  // The window has to be over the area vertically, not dropped above or below it.
  const centre = win.y + win.h / 2;
  if (centre < area.y || centre > area.y + area.h) {
    return null;
  }
  return centre < area.y + area.h / 2 ? 'top' : 'bottom';
}

/** The next mode a layout button asks for. */
export function pinRequest(mode: ChatMode, button: 'side' | 'float'): ChatMode {
  if (button === 'float') {
    return mode === 'float' ? 'bottom' : 'float';
  }
  return mode === 'top' ? 'bottom' : 'top';
}
