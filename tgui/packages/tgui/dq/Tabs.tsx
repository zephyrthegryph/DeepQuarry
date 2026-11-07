/**
 * The DQ tab row: every tab strip of the DQ UI (the stat panel's tabs, the
 * chat's, the Inspect and MC sub-tabs). A flat tgui-core Tabs list sitting on
 * the row's 2px bottom rule, so the selected tab's underline lands on that
 * rule whatever else the row holds; `children` go at the row's end (buttons,
 * a search box). With `onReorder` a tab drags along the strip, locked to its
 * axis and ends, while the others slide aside to make room; the new order
 * commits on release. Styles: tgui/styles/dq/tabs.scss.
 */

import { type ReactNode, useRef, useState } from 'react';
import { Tabs as CoreTabs } from 'tgui-core/components';
import { classes } from 'tgui-core/react';

export type Tab = {
  id: string;
  label: ReactNode;
  selected?: boolean;
  /** A tab that may not be dragged (a pinned tab). */
  fixed?: boolean;
  /** Hover text (a label cut short by the row). */
  title?: string;
};

/** How the row lays out its tabs: wrap onto more rows, one scrolling row, or the denser classic look. */
export type TabsLayout = 'wrap' | 'scrollable' | 'classic';

type Props = {
  tabs: Tab[];
  onSelect: (id: string) => void;
  /** Called with the new order when a dragged tab is released; omit to disable dragging. */
  onReorder?: (order: string[]) => void;
  layout?: TabsLayout;
  /** `small` for a sub-tab row inside a page (Inspect, MC). */
  size?: 'normal' | 'small';
  className?: string;
  /** Right after the last tab (an add-tab button). */
  afterTabs?: ReactNode;
  /** At the row's end (buttons, a search box). */
  children?: ReactNode;
};

/** Pixels the pointer must travel before a press on a tab becomes a drag (less is a click). */
export const DRAG_THRESHOLD = 4;

export type TabBox = { id: string; left: number; width: number; top: number };

/** Where the dragged tab lands: its centre against the centres of the other tabs in its row. */
export function dropIndex(boxes: TabBox[], id: string, dx: number): number {
  const from = boxes.findIndex((box) => box.id === id);
  if (from < 0) return -1;
  const dragged = boxes[from];
  const centre = dragged.left + dx + dragged.width / 2;
  let to = from;
  for (let i = 0; i < boxes.length; i++) {
    const box = boxes[i];
    if (i === from || box.top !== dragged.top) continue;
    const mid = box.left + box.width / 2;
    if (i > from && centre > mid) to = Math.max(to, i);
    if (i < from && centre < mid) to = Math.min(to, i);
  }
  return to;
}

/** The order with `id` moved to index `to`. */
export function moveTo(order: string[], id: string, to: number): string[] {
  const next = order.filter((item) => item !== id);
  next.splice(to, 0, id);
  return next;
}

/** How far the tab at `at` slides aside while the tab at `from` is dragged to `to`. */
export function slideFor(
  boxes: TabBox[],
  from: number,
  to: number,
  at: number,
): number {
  if (at === from || from < 0) return 0;
  const next = boxes[from + 1] ?? boxes[from - 1];
  const gap = next
    ? Math.max(
        0,
        next.left > boxes[from].left
          ? next.left - (boxes[from].left + boxes[from].width)
          : boxes[from].left - (next.left + next.width),
      )
    : 0;
  const room = boxes[from].width + gap;
  if (from < at && at <= to) return -room;
  if (from > at && at >= to) return room;
  return 0;
}

/** The dragged tab's offset held inside the strip: it slides along the row, never past its ends. */
export function clampDrag(
  box: TabBox,
  dx: number,
  minX: number,
  maxX: number,
): number {
  return Math.min(maxX - (box.left + box.width), Math.max(minX - box.left, dx));
}

type Drag = {
  id: string;
  pointerId: number;
  startX: number;
  boxes: TabBox[];
  minX: number;
  maxX: number;
  active: boolean;
};

export function Tabs(props: Props) {
  const {
    tabs,
    onSelect,
    onReorder,
    layout = 'wrap',
    size = 'normal',
    className,
    afterTabs,
    children,
  } = props;
  const strip = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const suppressClick = useRef(false);
  const [live, setLive] = useState<{ id: string; dx: number; to: number } | null>(
    null,
  );
  const ids = tabs.map((tab) => tab.id);

  function begin(event: React.PointerEvent, id: string) {
    if (!onReorder || event.button !== 0 || !strip.current) return;
    const bounds = strip.current.getBoundingClientRect();
    const boxes = Array.from(
      strip.current.querySelectorAll<HTMLElement>('[data-dq-tab]'),
    ).map((element) => {
      const rect = element.getBoundingClientRect();
      return {
        id: element.dataset.dqTab ?? '',
        left: rect.left,
        width: rect.width,
        top: Math.round(rect.top),
      };
    });
    drag.current = {
      id,
      pointerId: event.pointerId,
      startX: event.clientX,
      boxes,
      minX: bounds.left,
      maxX: bounds.right,
      active: false,
    };
  }

  function move(event: React.PointerEvent) {
    const current = drag.current;
    if (!current || event.pointerId !== current.pointerId) return;
    const raw = event.clientX - current.startX;
    if (!current.active) {
      if (Math.abs(raw) < DRAG_THRESHOLD) return;
      current.active = true;
      try {
        // Keep the drag while the pointer leaves the tab; the strip clamp keeps the tab in place.
        (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
      } catch {
        // A pointer the browser no longer tracks: the drag still follows the moves it gets.
      }
    }
    const box = current.boxes.find((b) => b.id === current.id);
    const dx = box ? clampDrag(box, raw, current.minX, current.maxX) : raw;
    setLive({ id: current.id, dx, to: dropIndex(current.boxes, current.id, dx) });
  }

  function finish(event: React.PointerEvent, commit: boolean) {
    const current = drag.current;
    if (!current || event.pointerId !== current.pointerId) return;
    drag.current = null;
    if (current.active) {
      suppressClick.current = true;
      const from = ids.indexOf(current.id);
      const to = live?.to ?? from;
      if (commit && onReorder && to >= 0 && to !== from) {
        onReorder(moveTo(ids, current.id, to));
      }
    }
    setLive(null);
  }

  const boxes = drag.current?.boxes ?? [];
  const from = live ? boxes.findIndex((b) => b.id === live.id) : -1;

  return (
    <div
      className={classes([
        'DqTabs',
        `DqTabs--${layout}`,
        size === 'small' && 'DqTabs--small',
        live && 'DqTabs--dragging',
        className,
      ])}
    >
      <div className="DqTabs__strip" ref={strip}>
        <CoreTabs className="DqTabs__list">
          {tabs.map((tab) => {
            const movable = !!onReorder && !tab.fixed;
            const dragged = live?.id === tab.id;
            const at = boxes.findIndex((b) => b.id === tab.id);
            const offset = !live
              ? 0
              : dragged
                ? live.dx
                : slideFor(boxes, from, live.to, at);
            return (
              <CoreTabs.Tab
                key={tab.id}
                selected={tab.selected}
                // tgui-core types no data-* props; Box passes them through to the element.
                {...({ 'data-dq-tab': tab.id } as object)}
                className={classes([
                  movable && 'DqTabs__tab--movable',
                  dragged && 'DqTabs__tab--dragged',
                ])}
                style={
                  offset ? { transform: `translateX(${offset}px)` } : undefined
                }
                onClick={() => {
                  if (suppressClick.current) {
                    suppressClick.current = false;
                    return;
                  }
                  onSelect(tab.id);
                }}
                onPointerDown={
                  movable
                    ? (event: React.PointerEvent) => begin(event, tab.id)
                    : undefined
                }
                onPointerMove={movable ? move : undefined}
                onPointerUp={
                  movable
                    ? (event: React.PointerEvent) => finish(event, true)
                    : undefined
                }
                onPointerCancel={
                  movable
                    ? (event: React.PointerEvent) => finish(event, false)
                    : undefined
                }
              >
                {tab.title ? (
                  <span title={tab.title}>{tab.label}</span>
                ) : (
                  tab.label
                )}
              </CoreTabs.Tab>
            );
          })}
        </CoreTabs>
      </div>
      {afterTabs !== undefined && (
        <div className="DqTabs__after">{afterTabs}</div>
      )}
      {children !== undefined && <div className="DqTabs__end">{children}</div>}
    </div>
  );
}
