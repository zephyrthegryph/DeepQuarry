/**
 * @file
 * Where a window pulled out of the right-hand column opens and follows the pointer, as pure maths (physical screen pixels): the
 * float text the server hands the new native window ("x,y" or "x,y,w,h"), the window place under the pointer, the size it keeps
 * from the column, and what a live drag of the native window sends each frame so only its place changes.
 */

export type Pair = [number, number];

/** How far below the pointer's y the window's top edge sits: the pointer holds the middle of the title bar. */
export const TITLE_GRAB = 16;

/** The smallest a window keeps coming out of the column (CSS pixels): a collapsed or very short entry still opens usable. */
export const FLOAT_MIN_CSS: Pair = [150, 120];

/** The float text for a pointer point and the size the window had in the column ("x,y,w,h"; "x,y" without a size). */
export function floatAtText(point: Pair, size?: Pair | null): string {
  const base = `${Math.round(point[0])},${Math.round(point[1])}`;
  return size ? `${base},${Math.round(size[0])},${Math.round(size[1])}` : base;
}

/** The point and optional size of a float text, or null when it is not one. */
export function parseFloatAt(
  at: string | null | undefined,
): { point: Pair; size: Pair | null } | null {
  const parts = typeof at === 'string' ? at.split(',').map(Number) : [];
  if (
    (parts.length !== 2 && parts.length !== 4) ||
    !parts.every(Number.isFinite)
  ) {
    return null;
  }
  const size: Pair | null =
    parts.length === 4 && parts[2] > 0 && parts[3] > 0
      ? [parts[2], parts[3]]
      : null;
  return { point: [parts[0], parts[1]], size };
}

/** The window place (top-left) that puts `point` on the middle of the title bar of a window `width` wide. */
export function placeUnder(point: Pair, width: number): Pair {
  return [Math.round(point[0] - width / 2), Math.round(point[1] - TITLE_GRAB)];
}

/** The window place a float text asks for, given the window's own size when the text carries none; null when there is no point. */
export function underPointer(
  at: string | null | undefined,
  size: Pair | undefined,
): Pair | null {
  const parsed = parseFloatAt(at);
  if (!parsed) return null;
  return placeUnder(parsed.point, (parsed.size ?? size)?.[0] ?? 0);
}

/**
 * The size a window floated from the column keeps: what its entry had there (CSS pixels, so the page's ratio converts it to
 * physical), never under FLOAT_MIN_CSS and never past `max` (physical).
 */
export function floatSize(
  docked: { w: number; h: number },
  ratio: number,
  max: Pair = [8000, 8000],
): Pair {
  const r = ratio > 0 ? ratio : 1;
  const w = Math.max(FLOAT_MIN_CSS[0], docked.w) * r;
  const h = Math.max(FLOAT_MIN_CSS[1], docked.h) * r;
  return [Math.round(Math.min(max[0], w)), Math.round(Math.min(max[1], h))];
}

/** The page measures its window in whole CSS pixels, so a window that kept its size still reads up to a ratio's worth of physical pixels off. */
export const DRIFT_TOLERANCE = 4;

/**
 * What one frame of a titlebar drag sends: the place always, the size only when the native window no longer has the size the drag
 * began with (the system rescaled it crossing monitors of another density, or a clamp moved it); a drag never changes size.
 */
export function dragFrame(
  pos: Pair,
  held: Pair,
  now: Pair,
): { pos: string; size?: string; drift: boolean } {
  const drift =
    Math.abs(now[0] - held[0]) > DRIFT_TOLERANCE ||
    Math.abs(now[1] - held[1]) > DRIFT_TOLERANCE;
  const out: { pos: string; size?: string; drift: boolean } = {
    pos: `${Math.round(pos[0])},${Math.round(pos[1])}`,
    drift,
  };
  if (drift) out.size = `${Math.round(held[0])}x${Math.round(held[1])}`;
  return out;
}
