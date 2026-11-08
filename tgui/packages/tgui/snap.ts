/** How close (physical pixels) a dragged window's edge must come to a screen edge to stick to it. */
export const SNAP_DISTANCE = 24;

/**
 * Where a window dragged to `pos` rests: each axis sticks to the screen edge it is within SNAP_DISTANCE of,
 * so a window brought into a corner sticks to both of its edges.
 */
export function snapToScreen(
  pos: [number, number],
  size: [number, number],
  screen: [number, number],
  distance = SNAP_DISTANCE,
): [number, number] {
  const axis = (at: number, length: number, limit: number) => {
    if (Math.abs(at) <= distance) return 0;
    const far = limit - length;
    return Math.abs(at - far) <= distance ? far : at;
  };
  return [axis(pos[0], size[0], screen[0]), axis(pos[1], size[1], screen[1])];
}
