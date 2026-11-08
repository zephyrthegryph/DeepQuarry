/**
 * Live re-arranging, as pure maths along one axis: while an item of a strip
 * or list is dragged, where it would land and how far each other item slides
 * aside to make room. One model for every drag-to-reorder surface of the DQ
 * UI (tab strips along x, the window dock's list along y), so they all move
 * the same way. `start`/`size` are an item's offset and extent on the axis;
 * `line` groups items that share a row (a wrapped tab strip), and only items
 * on the dragged one's line count.
 */

export type OrderBox = {
  id: string;
  start: number;
  size: number;
  line?: number;
};

/** Pixels the pointer travels before a press becomes a drag (less is a click). */
export const DRAG_THRESHOLD = 4;

/** Where the dragged item lands: its centre against the other items' centres. */
export function liveDropIndex(
  boxes: OrderBox[],
  id: string,
  delta: number,
): number {
  const from = boxes.findIndex((box) => box.id === id);
  if (from < 0) return -1;
  const dragged = boxes[from];
  const centre = dragged.start + delta + dragged.size / 2;
  let to = from;
  for (let i = 0; i < boxes.length; i++) {
    const box = boxes[i];
    if (i === from || (box.line ?? 0) !== (dragged.line ?? 0)) continue;
    const mid = box.start + box.size / 2;
    if (i > from && centre > mid) to = Math.max(to, i);
    if (i < from && centre < mid) to = Math.min(to, i);
  }
  return to;
}

/** How far the item at `at` slides while the item at `from` is dragged to `to`. */
export function liveSlide(
  boxes: OrderBox[],
  from: number,
  to: number,
  at: number,
): number {
  if (at === from || from < 0 || !boxes[from]) return 0;
  const self = boxes[from];
  const next = boxes[from + 1] ?? boxes[from - 1];
  const gap = next
    ? Math.max(
        0,
        next.start > self.start
          ? next.start - (self.start + self.size)
          : self.start - (next.start + next.size),
      )
    : 0;
  const room = self.size + gap;
  if (from < at && at <= to) return -room;
  if (from > at && at >= to) return room;
  return 0;
}

/** The dragged item's offset held inside [min, max]: it slides along, never past the ends. */
export function liveClamp(
  box: OrderBox,
  delta: number,
  min: number,
  max: number,
): number {
  return Math.min(
    max - (box.start + box.size),
    Math.max(min - box.start, delta),
  );
}

/** The order with `id` moved to index `to`. */
export function moveTo<T>(order: T[], id: T, to: number): T[] {
  const next = order.filter((item) => item !== id);
  next.splice(to, 0, id);
  return next;
}
