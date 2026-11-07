/** Pure placement and size rules for the say popup (no Byond or DOM access, so they test alone). */

export type Rect = { x: number; y: number; w: number; h: number };
export type Point = { x: number; y: number };
export type Size = { w: number; h: number };

/** Smallest popup, in CSS pixels: room for the channel button, a usable input and the close button. */
export const MIN_WIDTH = 300;
/** One input line; the language preview adds its own height on top. */
export const MIN_HEIGHT = 30;

/** How much of the popup must overlap a screen for the player to still reach it. */
export const MIN_VISIBLE = { w: 40, h: 16 };

/**
 * Used when the client cannot list its monitors: the Windows virtual desktop
 * spans -32768..32767 on each axis, so a window past it is on no screen.
 */
export const VIRTUAL_DESKTOP: Rect = {
  x: -32768,
  y: -32768,
  w: 65536,
  h: 65536,
};

/** A requested size in CSS pixels, raised to the minimum. */
export function clampCssSize(w: number, h: number): Size {
  return {
    w: Math.max(Number.isFinite(w) ? w : MIN_WIDTH, MIN_WIDTH),
    h: Math.max(Number.isFinite(h) ? h : MIN_HEIGHT, MIN_HEIGHT),
  };
}

/** The minimum in native pixels for a CSS-to-native factor (the device ratio, or 1 when unscaled). */
export function minNativeSize(factor: number): Size {
  const f = Number.isFinite(factor) && factor > 0 ? factor : 1;
  return { w: Math.round(MIN_WIDTH * f), h: Math.round(MIN_HEIGHT * f) };
}

/** The size to restore when the window is smaller than the minimum on either axis, else null. */
export function sizeToRestore(actual: Size, min: Size): Size | null {
  if (actual.w >= min.w && actual.h >= min.h) return null;
  return { w: Math.max(actual.w, min.w), h: Math.max(actual.h, min.h) };
}

const overlap = (aStart: number, aLen: number, bStart: number, bLen: number) =>
  Math.min(aStart + aLen, bStart + bLen) - Math.max(aStart, bStart);

/**
 * Whether a popup at `pos` can still be reached: enough of it overlaps some
 * screen to grab. Outside the game window is fine; only being off every
 * screen fails.
 */
export function isReachable(
  pos: Point,
  size: Size,
  screens: Rect[],
  visible: Size = MIN_VISIBLE,
): boolean {
  const need = {
    w: Math.min(visible.w, size.w),
    h: Math.min(visible.h, size.h),
  };
  return screens.some(
    (s) =>
      overlap(pos.x, size.w, s.x, s.w) >= need.w &&
      overlap(pos.y, size.h, s.y, s.h) >= need.h,
  );
}

/** A stored position, or null when the stored value is not a usable one. */
export function parseStoredPosition(value: unknown): Point | null {
  if (!value || typeof value !== 'object') return null;
  const { x, y } = value as Point;
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return { x: Math.round(x), y: Math.round(y) };
}

/** Whether a pointer moved far enough between press and release to count as a drag, not a click. */
export function isDragMove(from: Point, to: Point, threshold = 4): boolean {
  return (
    Math.abs(to.x - from.x) >= threshold || Math.abs(to.y - from.y) >= threshold
  );
}
