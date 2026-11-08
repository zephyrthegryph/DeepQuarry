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
import {
  DRAG_THRESHOLD,
  liveClamp,
  liveDropIndex,
  liveSlide,
  moveTo,
  type OrderBox,
} from './liveOrder';

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
  /**
   * Pulling a tab off the strip (across it, past DRAG_OUT_DISTANCE) hands the
   * drag to the caller with the live pointer event: the strip drops its
   * re-arranging and the caller carries on (the window dock pulls a docked
   * window out of a stack this way). Omit to keep tabs locked to the strip.
   */
  onDragOut?: (id: string, event: PointerEvent) => void;
  /** Right after the last tab (an add-tab button). */
  afterTabs?: ReactNode;
  /** At the row's end (buttons, a search box). */
  children?: ReactNode;
};

export { DRAG_THRESHOLD, moveTo } from './liveOrder';

/** How far (CSS px) a tab is pulled off its strip, across it, before `onDragOut` takes the drag. */
export const DRAG_OUT_DISTANCE = 14;

export type TabBox = { id: string; left: number; width: number; top: number };

const asOrder = (box: TabBox): OrderBox => ({
  id: box.id,
  start: box.left,
  size: box.width,
  line: box.top,
});

/** Where the dragged tab lands (the shared live-order model, tgui/dq/liveOrder.ts, along x). */
export function dropIndex(boxes: TabBox[], id: string, dx: number): number {
  return liveDropIndex(boxes.map(asOrder), id, dx);
}

/** How far the tab at `at` slides aside while the tab at `from` is dragged to `to`. */
export function slideFor(
  boxes: TabBox[],
  from: number,
  to: number,
  at: number,
): number {
  return liveSlide(boxes.map(asOrder), from, to, at);
}

/** The dragged tab's offset held inside the strip. */
export function clampDrag(
  box: TabBox,
  dx: number,
  minX: number,
  maxX: number,
): number {
  return liveClamp(asOrder(box), dx, minX, maxX);
}

type Drag = {
  id: string;
  pointerId: number;
  startX: number;
  startY: number;
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
    onDragOut,
    layout = 'wrap',
    size = 'normal',
    className,
    afterTabs,
    children,
  } = props;
  const strip = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const suppressClick = useRef(false);
  const [live, setLive] = useState<{
    id: string;
    dx: number;
    to: number;
  } | null>(null);
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
      startY: event.clientY,
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
      if (
        Math.abs(raw) < DRAG_THRESHOLD &&
        !(
          onDragOut &&
          Math.abs(event.clientY - current.startY) >= DRAG_THRESHOLD
        )
      )
        return;
      current.active = true;
      try {
        // Keep the drag while the pointer leaves the tab; the strip clamp keeps the tab in place.
        (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
      } catch {
        // A pointer the browser no longer tracks: the drag still follows the moves it gets.
      }
    }
    if (
      onDragOut &&
      Math.abs(event.clientY - current.startY) >= DRAG_OUT_DISTANCE
    ) {
      // Off the strip: the caller owns the drag from here.
      drag.current = null;
      suppressClick.current = true;
      setLive(null);
      onDragOut(current.id, event.nativeEvent);
      return;
    }
    const box = current.boxes.find((b) => b.id === current.id);
    const dx = box ? clampDrag(box, raw, current.minX, current.maxX) : raw;
    setLive({
      id: current.id,
      dx,
      to: dropIndex(current.boxes, current.id, dx),
    });
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
                // tgui-core's Tab types neither data-* nor pointer props; Box passes both through to the element.
                {...({
                  'data-dq-tab': tab.id,
                  ...(movable && {
                    onPointerDown: (event: React.PointerEvent) =>
                      begin(event, tab.id),
                    onPointerMove: move,
                    onPointerUp: (event: React.PointerEvent) =>
                      finish(event, true),
                    onPointerCancel: (event: React.PointerEvent) =>
                      finish(event, false),
                  }),
                } as object)}
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
