/**
 * Moves `dragged` to `target`'s place in `order`: dragged down it lands after
 * the target, dragged up before it. The list comes back as is when nothing
 * moves (the same item, or one that is not in the list). Shared by every
 * drag-to-reorder list (console tabs, the abilities grid).
 */
export function moveBefore<T>(order: T[], dragged: T, target: T): T[] {
  const from = order.indexOf(dragged);
  const to = order.indexOf(target);
  if (from < 0 || to < 0 || from === to) return order;
  const next = order.filter((item) => item !== dragged);
  next.splice(to, 0, dragged);
  return next;
}
