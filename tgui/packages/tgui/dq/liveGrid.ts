/**
 * Live re-arranging for a wrapping grid (the abilities grid): the same
 * gesture as the DQ tab strip and the window dock (tgui/dq/liveOrder.ts),
 * where items wrap onto rows. While an item is dragged the grid shows the
 * order it would commit (the others reflow around it) and the order commits on
 * release; a press that never passes DRAG_THRESHOLD stays a click.
 */
import { useRef, useState } from 'react';
import { DRAG_THRESHOLD, moveTo } from './liveOrder';

export type GridRect = {
  id: string;
  left: number;
  top: number;
  width: number;
  height: number;
};

/**
 * The index the dragged item takes with the pointer at (x, y): the item the
 * pointer is over, else the nearest one by its centre. -1 when there are none.
 */
export function gridDropIndex(rects: GridRect[], x: number, y: number): number {
  let best = -1;
  let bestGap = Number.POSITIVE_INFINITY;
  rects.forEach((rect, index) => {
    if (
      x >= rect.left &&
      x <= rect.left + rect.width &&
      y >= rect.top &&
      y <= rect.top + rect.height
    ) {
      best = index;
      bestGap = -1;
      return;
    }
    if (bestGap < 0) return;
    const gap = Math.hypot(
      x - (rect.left + rect.width / 2),
      y - (rect.top + rect.height / 2),
    );
    if (gap < bestGap) {
      best = index;
      bestGap = gap;
    }
  });
  return best;
}

type Press = {
  id: string;
  pointerId: number;
  x: number;
  y: number;
  rects: GridRect[];
  active: boolean;
};

/**
 * The live grid gesture. `order` is the committed order; spread
 * `itemProps(id)` on each item (it needs `data-live-id`); render `shown` (the
 * order the drag would commit, or `order`) and mark `dragging`. `onCommit`
 * gets the new order on release; `consumeClick()` says a click was the end of
 * a drag.
 */
export function useLiveGrid(
  order: string[],
  onCommit: (order: string[]) => void,
) {
  const press = useRef<Press | null>(null);
  const suppress = useRef(false);
  const [live, setLive] = useState<{ id: string; to: number } | null>(null);
  const shown = live ? moveTo(order, live.id, live.to) : order;

  const measure = (node: HTMLElement): GridRect[] => {
    const root = node.closest('[data-live-grid]') ?? node.parentElement;
    return Array.from(
      root?.querySelectorAll<HTMLElement>('[data-live-id]') ?? [],
    ).map((el) => {
      const r = el.getBoundingClientRect();
      return {
        id: el.dataset.liveId ?? '',
        left: r.left,
        top: r.top,
        width: r.width,
        height: r.height,
      };
    });
  };

  const itemProps = (id: string) => ({
    'data-live-id': id,
    onPointerDown: (event: React.PointerEvent<HTMLElement>) => {
      if (event.button !== 0) return;
      press.current = {
        id,
        pointerId: event.pointerId,
        x: event.clientX,
        y: event.clientY,
        rects: measure(event.currentTarget),
        active: false,
      };
    },
    onPointerMove: (event: React.PointerEvent<HTMLElement>) => {
      const p = press.current;
      if (!p || event.pointerId !== p.pointerId) return;
      if (!p.active) {
        if (
          Math.hypot(event.clientX - p.x, event.clientY - p.y) < DRAG_THRESHOLD
        )
          return;
        p.active = true;
        try {
          event.currentTarget.setPointerCapture(event.pointerId);
        } catch {
          // Not tracked any more: the drag follows the moves it gets.
        }
      }
      // Measured at the press: the committed layout, so the target never jitters as the preview reflows.
      const to = gridDropIndex(p.rects, event.clientX, event.clientY);
      if (to >= 0 && (live?.to !== to || live.id !== p.id)) {
        setLive({ id: p.id, to });
      }
    },
    onPointerUp: (event: React.PointerEvent<HTMLElement>) => {
      const p = press.current;
      if (!p || event.pointerId !== p.pointerId) return;
      press.current = null;
      if (p.active) {
        suppress.current = true;
        const next = live ? moveTo(order, p.id, live.to) : order;
        if (next.some((item, i) => item !== order[i])) onCommit(next);
      }
      setLive(null);
    },
    onPointerCancel: () => {
      press.current = null;
      setLive(null);
    },
  });

  /** True once after a drag ended (the click that follows is not a press). */
  const consumeClick = () => {
    const was = suppress.current;
    suppress.current = false;
    return was;
  };

  return { shown, dragging: live?.id ?? null, itemProps, consumeClick };
}
