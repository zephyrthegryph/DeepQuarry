/** How close (physical pixels) a dragged window's edge must come to a screen edge to stick to it. */
export const SNAP_DISTANCE = 24;

/**
 * Where a window dragged to `pos` rests: each axis sticks to the screen edge it is within SNAP_DISTANCE of,
 * so a window brought into a corner sticks to both of its edges. `origin` is the screen's top-left (a monitor left of or above the primary has
 * a negative one) and `screen` its size, in the same pixels as `pos`.
 */
export function snapToScreen(
  pos: [number, number],
  size: [number, number],
  screen: [number, number],
  distance = SNAP_DISTANCE,
  origin: [number, number] = [0, 0],
): [number, number] {
  const axis = (at: number, length: number, limit: number, from: number) => {
    if (Math.abs(at - from) <= distance) return from;
    const far = from + limit - length;
    return Math.abs(at - far) <= distance ? far : at;
  };
  return [
    axis(pos[0], size[0], screen[0], origin[0]),
    axis(pos[1], size[1], screen[1], origin[1]),
  ];
}
