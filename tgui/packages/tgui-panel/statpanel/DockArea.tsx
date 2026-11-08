/**
 * The window dock's frame in the stat panel (doc/rewrite/proposals/window_system.md):
 * one entry per group, its titlebar (or tabs for a stack), collapse, float and
 * close, a resize grip, and a placeholder the group's window is placed over
 * (dockHost.ts). It moves the way the chat does, on the shared DQ model
 * (tgui/dq liveOrder.ts, the one the tab strips use):
 * - the free space of a header drags the whole entry along the list while the
 *   others slide aside, onto another entry's header to stack there, or out of
 *   the panel (the chat's pop-out distance) to float under the pointer;
 * - a stack's tabs are the DQ tab strip: a click selects, a drag along the
 *   strip re-arranges them live, and pulling one off the strip takes that
 *   window out: to its own entry where it is dropped, onto another header, or
 *   out of the panel to float.
 */
import {
  type PointerEvent as ReactPointerEvent,
  useState,
  useSyncExternalStore,
} from 'react';
import {
  DRAG_THRESHOLD,
  liveClamp,
  liveDropIndex,
  liveSlide,
  type OrderBox,
  Tabs,
} from 'tgui/dq';
import { Button } from 'tgui-core/components';
import { POP_OUT_DISTANCE } from '../layout/model';
import { type DockHost, dockHost } from './dockHost';
import type { DockGroup } from './windowDock';

/** Presses here keep their own meaning (buttons click, tabs select and re-arrange). */
const NO_DRAG = 'button, input, .Button, .Tab, [data-dq-tab]';

/** A drag in progress, as the list should show it now. */
export type GroupDrag = {
  group: string;
  /** A single tab pulled out of the stack (null: the whole entry moves). */
  window: string | null;
  /** The dragged entry's offset along the list, held inside it. */
  dy: number;
  /** The list index it would land at. */
  to: number;
  /** The group whose header it is over (stacks into it), or null. */
  join: string | null;
  /** Out of the panel far enough to float. */
  float: boolean;
  boxes: OrderBox[];
};

/** Whether a page point is out of the panel by at least the chat's pop-out distance. */
export function outOfPanel(x: number, y: number, w: number, h: number) {
  const d = POP_OUT_DISTANCE;
  return x < -d || y < -d || x > w + d || y > h + d;
}

/** The list index a page y falls at, against the entries' middles. */
export function indexAtY(boxes: OrderBox[], y: number): number {
  const at = boxes.findIndex((box) => y < box.start + box.size / 2);
  return at < 0 ? boxes.length : at;
}

/** The vertical offset of `group` while `drag` is live (the dragged one follows the pointer, the rest slide). */
export function groupOffset(drag: GroupDrag | null, group: string): number {
  if (!drag || drag.window) {
    return 0;
  }
  if (drag.group === group) {
    return drag.float ? 0 : drag.dy;
  }
  if (drag.float || drag.join) {
    return 0;
  }
  const from = drag.boxes.findIndex((b) => b.id === drag.group);
  const at = drag.boxes.findIndex((b) => b.id === group);
  return liveSlide(drag.boxes, from, drag.to, at);
}

function measure(area: HTMLElement): OrderBox[] {
  return Array.from(
    area.querySelectorAll<HTMLElement>('[data-dock-group]'),
  ).map((node) => {
    const rect = node.getBoundingClientRect();
    return {
      id: node.dataset.dockGroup ?? '',
      start: rect.top,
      size: rect.height,
    };
  });
}

function headUnder(x: number, y: number, skip: string): string | null {
  for (const node of Array.from(
    document.querySelectorAll<HTMLElement>('[data-dock-head]'),
  )) {
    if (node.dataset.dockHead === skip) continue;
    const r = node.getBoundingClientRect();
    if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
      return node.dataset.dockHead ?? null;
    }
  }
  return null;
}

/** A live drag of an entry (`pulled` null) or of one tab pulled out of its stack. */
function runDrag(
  target: Element,
  pointer: number,
  start: { x: number; y: number },
  host: DockHost,
  group: string,
  pulled: string | null,
  setDrag: (drag: GroupDrag | null) => void,
  first?: PointerEvent,
) {
  const areaNode = host.areaNode;
  if (!areaNode) {
    return;
  }
  try {
    target.setPointerCapture(pointer);
  } catch {
    // Not tracked any more: the drag follows the moves it gets.
  }
  const boxes = measure(areaNode);
  const area = areaNode.getBoundingClientRect();
  const min = area.top;
  const max = Math.max(area.bottom, boxes.at(-1)?.start ?? 0);
  host.setDragging(true);
  let live: GroupDrag | null = null;
  const move = (e: PointerEvent) => {
    if (e.pointerId !== pointer) return;
    const box = boxes.find((b) => b.id === group);
    const dy =
      !pulled && box ? liveClamp(box, e.clientY - start.y, min, max) : 0;
    const float = outOfPanel(
      e.clientX,
      e.clientY,
      window.innerWidth,
      window.innerHeight,
    );
    // A pulled tab dropped back on its own header goes back where it was.
    const join = float ? null : headUnder(e.clientX, e.clientY, group);
    live = {
      group,
      window: pulled,
      dy,
      to: pulled ? indexAtY(boxes, e.clientY) : liveDropIndex(boxes, group, dy),
      join,
      float,
      boxes,
    };
    setDrag(live);
  };
  const end = (e: PointerEvent) => {
    if (e.pointerId !== pointer) return;
    document.removeEventListener('pointermove', move);
    document.removeEventListener('pointerup', end);
    document.removeEventListener('pointercancel', end);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
    const done = live;
    setDrag(null);
    host.setDragging(false);
    if (!done || e.type !== 'pointerup') {
      return;
    }
    const at = host.screenPoint(e.clientX, e.clientY);
    if (pulled) {
      if (done.float) {
        host.float(pulled, at);
      } else if (done.join) {
        const into = host.state.groups.find((g) => g.id === done.join);
        host.dispatch({
          type: 'moveWindow',
          id: pulled,
          group: done.join,
          index: into?.windows.length ?? 0,
        });
      } else {
        host.dispatch({ type: 'splitWindow', id: pulled, index: done.to });
      }
      return;
    }
    if (done.float) {
      host.floatGroup(group, at);
    } else if (done.join) {
      host.dispatch({ type: 'joinGroup', group, into: done.join });
    } else {
      // moveGroup counts positions before the move; the live index is the one after.
      const from = done.boxes.findIndex((b) => b.id === group);
      host.dispatch({
        type: 'moveGroup',
        group,
        index: done.to > from ? done.to + 1 : done.to,
      });
    }
  };
  // On the document: captured events still bubble there, whichever element holds the capture.
  document.addEventListener('pointermove', move);
  document.addEventListener('pointerup', end);
  document.addEventListener('pointercancel', end);
  if (first) move(first);
}

/** A press on a header's free space: past the drag threshold it moves the whole entry. */
function pressHead(
  event: ReactPointerEvent<HTMLElement>,
  host: DockHost,
  group: DockGroup,
  setDrag: (drag: GroupDrag | null) => void,
) {
  if (
    event.button !== 0 ||
    (event.target as HTMLElement).closest?.(NO_DRAG) ||
    !host.areaNode
  ) {
    return;
  }
  const target = event.currentTarget;
  const pointer = event.pointerId;
  const start = { x: event.clientX, y: event.clientY };
  const stop = () => {
    document.removeEventListener('pointermove', wait);
    document.removeEventListener('pointerup', stop);
    document.removeEventListener('pointercancel', stop);
  };
  const wait = (e: PointerEvent) => {
    if (e.pointerId !== pointer) return;
    if (Math.hypot(e.clientX - start.x, e.clientY - start.y) < DRAG_THRESHOLD)
      return;
    stop();
    runDrag(target, pointer, start, host, group.id, null, setDrag, e);
  };
  document.addEventListener('pointermove', wait);
  document.addEventListener('pointerup', stop);
  document.addEventListener('pointercancel', stop);
}

function startResize(
  event: ReactPointerEvent<HTMLElement>,
  host: DockHost,
  group: DockGroup,
) {
  if (event.button !== 0) {
    return;
  }
  event.stopPropagation();
  const target = event.currentTarget;
  const pointer = event.pointerId;
  const startY = event.clientY;
  const startHeight = group.height;
  target.setPointerCapture(pointer);
  const move = (e: PointerEvent) =>
    host.dispatch({
      type: 'resize',
      group: group.id,
      height: startHeight + e.clientY - startY,
    });
  const end = () => {
    target.removeEventListener('pointermove', move);
    target.removeEventListener('pointerup', end);
    target.removeEventListener('pointercancel', end);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
  };
  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
}

function ghostText(drag: GroupDrag | null, group: string, title: string) {
  if (drag?.join === group) {
    return 'Release to stack here';
  }
  if (drag?.group === group && drag.float && !drag.window) {
    return 'Release to float';
  }
  return title;
}

function Group(props: {
  group: DockGroup;
  index: number;
  host: DockHost;
  drag: GroupDrag | null;
  setDrag: (drag: GroupDrag | null) => void;
}) {
  const { group, index, host, drag, setDrag } = props;
  const { windows } = host.state;
  const active = windows[group.active];
  const title = active?.title || active?.iface || '';
  const stacked = group.windows.length > 1;
  const dragged = drag?.group === group.id && !drag.window;
  const lit = drag?.join === group.id;
  const insert =
    !!drag?.window && !drag.float && !drag.join && drag.to === index;
  const offset = groupOffset(drag, group.id);
  const toggle = () =>
    host.dispatch({
      type: 'collapse',
      group: group.id,
      collapsed: !group.collapsed,
    });
  return (
    <div
      className={[
        'dock-group',
        dragged && 'dock-group--dragged',
        dragged && drag?.float && 'dock-group--floating',
        insert && 'dock-group--insert',
      ]
        .filter(Boolean)
        .join(' ')}
      data-dock-group={group.id}
      style={offset ? { transform: `translateY(${offset}px)` } : undefined}
    >
      <div
        className={`dock-head${lit ? ' dock-head--lit' : ''}`}
        data-dock-head={group.id}
        onPointerDown={(event) => pressHead(event, host, group, setDrag)}
        onDoubleClick={(event) => {
          if (!(event.target as HTMLElement).closest(NO_DRAG)) toggle();
        }}
      >
        <Button
          compact
          color="transparent"
          icon={group.collapsed ? 'chevron-right' : 'chevron-down'}
          tooltip={group.collapsed ? 'Expand' : 'Collapse'}
          onClick={toggle}
        />
        {stacked ? (
          <Tabs
            className="dock-tabs"
            layout="scrollable"
            tabs={group.windows.map((id) => ({
              id,
              label: windows[id]?.title || windows[id]?.iface,
              selected: id === group.active,
            }))}
            onSelect={(id) => host.dispatch({ type: 'activate', id })}
            onReorder={(order) =>
              host.dispatch({ type: 'orderTabs', group: group.id, order })
            }
            onDragOut={(id, event) =>
              runDrag(
                event.target as Element,
                event.pointerId,
                { x: event.clientX, y: event.clientY },
                host,
                group.id,
                id,
                setDrag,
                event,
              )
            }
          />
        ) : (
          <span className="dock-title">{title}</span>
        )}
        <Button
          compact
          color="transparent"
          icon="up-right-from-square"
          tooltip="Float"
          onClick={() => host.float(group.active)}
        />
        <Button
          compact
          color="transparent"
          icon="times"
          tooltip="Close"
          onClick={() => host.close(group.active)}
        />
      </div>
      {!group.collapsed && (
        <div
          className="dock-body"
          style={{ height: `${group.height}px` }}
          ref={(node) => host.setBody(group.active, node)}
        >
          {host.dragging && (
            <div className="dock-body__ghost">
              {ghostText(drag, group.id, title)}
            </div>
          )}
          <div
            className="dock-grip"
            onPointerDown={(event) => startResize(event, host, group)}
          />
        </div>
      )}
    </div>
  );
}

export function DockArea() {
  const host = dockHost;
  useSyncExternalStore(host.subscribe, host.getVersion);
  const [drag, setDrag] = useState<GroupDrag | null>(null);
  const { groups } = host.state;
  if (!groups.length) {
    return null;
  }
  const insertEnd =
    !!drag?.window && !drag.float && !drag.join && drag.to >= groups.length;
  return (
    <div
      className={`dock-area${host.dragging ? ' dock-area--dragging' : ''}`}
      ref={(node) => host.setArea(node)}
      onScroll={host.schedule}
    >
      {groups.map((group, index) => (
        <Group
          key={group.id}
          group={group}
          index={index}
          host={host}
          drag={drag}
          setDrag={setDrag}
        />
      ))}
      {insertEnd && <div className="dock-insert-end" />}
    </div>
  );
}
