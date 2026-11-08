/**
 * The right-hand column (doc/rewrite/proposals/window_system.md section 12):
 * one page, one window manager. Every window in it, the chat, the stat
 * panel's views and docked tgui interfaces, is an entry of the same list,
 * framed the same way and moved by the same code:
 * - an entry's header shows its title, or its tabs when windows are stacked;
 *   its chevron (or a double click) collapses it to the header;
 * - the free space of a header drags the whole entry along the list while the
 *   others slide aside (live, tgui/dq liveOrder), onto another header to stack
 *   there, or out of the page to float (docked interfaces become native
 *   windows under the pointer);
 * - stack tabs are the DQ tab strip: a click selects, a drag along the strip
 *   re-arranges, pulling one off the strip takes that window out;
 * - the grip under an expanded entry resizes it; the last expanded entry
 *   fills what is left.
 */
import {
  Component,
  type ErrorInfo,
  type ReactNode,
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
import 'tgui/embeddedStyles';
import { EmbeddedInterface } from 'tgui/routes';
import { Button } from 'tgui-core/components';
import { MapSplitHandle } from '../layout/ChatLayout';
import { POP_OUT_DISTANCE } from '../layout/model';
import { Panel } from '../Panel';
import { type ColumnHost, columnHost } from './host';
import type { DockGroup, DockWindow } from './model';

/** Presses here keep their own meaning (buttons click, tabs select and re-arrange). */
const NO_DRAG = 'button, input, .Button, .Tab, [data-dq-tab]';

/** A drag in progress, as the list should show it now. */
export type GroupDrag = {
  group: string;
  /** A single tab pulled out of its stack (null: the whole entry moves). */
  window: string | null;
  /** The dragged entry's offset along the list, held inside it. */
  dy: number;
  /** The list index it would land at. */
  to: number;
  /** The group whose header it is over (stacks into it), or null. */
  join: string | null;
  /** Out of the page far enough to float. */
  float: boolean;
  boxes: OrderBox[];
};

/** Whether a page point is out of the page by at least the chat's pop-out distance. */
export function outOfPage(x: number, y: number, w: number, h: number) {
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

/** Whether a window can leave the page as a native window (only docked tgui interfaces have one to go to). */
export const canFloat = (win?: DockWindow) => win?.kind === 'tgui';

function measure(): OrderBox[] {
  return Array.from(
    document.querySelectorAll<HTMLElement>('[data-column-group]'),
  ).map((node) => {
    const rect = node.getBoundingClientRect();
    return {
      id: node.dataset.columnGroup ?? '',
      start: rect.top,
      size: rect.height,
    };
  });
}

function headUnder(x: number, y: number, skip: string): string | null {
  for (const node of Array.from(
    document.querySelectorAll<HTMLElement>('[data-column-head]'),
  )) {
    if (node.dataset.columnHead === skip) continue;
    const r = node.getBoundingClientRect();
    if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
      return node.dataset.columnHead ?? null;
    }
  }
  return null;
}

/** The screen point (physical pixels) of a page point, for a window floated under the pointer. */
function screenPoint(e: PointerEvent) {
  const ratio = window.devicePixelRatio || 1;
  return {
    x: Math.round(e.screenX * ratio),
    y: Math.round(e.screenY * ratio),
  };
}

/** A live drag of an entry (`pulled` null) or of one tab pulled out of its stack. */
function runDrag(
  target: Element,
  pointer: number,
  start: { x: number; y: number },
  host: ColumnHost,
  group: string,
  pulled: string | null,
  setDrag: (drag: GroupDrag | null) => void,
  first?: PointerEvent,
) {
  try {
    target.setPointerCapture(pointer);
  } catch {
    // Not tracked any more: the drag follows the moves it gets.
  }
  const boxes = measure();
  const min = 0;
  const max = Math.max(window.innerHeight, boxes.at(-1)?.start ?? 0);
  const groupOf = host.state.groups.find((g) => g.id === group);
  const floatable = pulled
    ? canFloat(host.windowOf(pulled))
    : !!groupOf?.windows.every((id) => canFloat(host.windowOf(id)));
  let live: GroupDrag | null = null;
  const move = (e: PointerEvent) => {
    if (e.pointerId !== pointer) return;
    const box = boxes.find((b) => b.id === group);
    const dy =
      !pulled && box ? liveClamp(box, e.clientY - start.y, min, max) : 0;
    const float =
      floatable &&
      outOfPage(e.clientX, e.clientY, window.innerWidth, window.innerHeight);
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
    if (!done || e.type !== 'pointerup') {
      return;
    }
    if (pulled) {
      if (done.float) {
        host.float(pulled, screenPoint(e));
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
      for (const id of groupOf?.windows ?? []) {
        host.float(id, id === groupOf?.active ? screenPoint(e) : null);
      }
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
  host: ColumnHost,
  group: DockGroup,
  setDrag: (drag: GroupDrag | null) => void,
) {
  if (event.button !== 0 || (event.target as HTMLElement).closest?.(NO_DRAG)) {
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
  host: ColumnHost,
  group: DockGroup,
) {
  if (event.button !== 0) {
    return;
  }
  event.stopPropagation();
  const target = event.currentTarget;
  const pointer = event.pointerId;
  const startY = event.clientY;
  const body = target.parentElement?.getBoundingClientRect();
  const startHeight = body ? Math.round(body.height) : group.height;
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

/** One window's content failing to draw shows a short error in its place; the rest of the column keeps working. */
class WindowBoundary extends Component<
  { name: string; children: ReactNode },
  { error: boolean }
> {
  state = { error: false };

  static getDerivedStateFromError() {
    return { error: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error(`column window "${this.props.name}" failed`, error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div className="column-window__error">
          {this.props.name} failed to draw.{' '}
          <Button onClick={() => this.setState({ error: false })}>Retry</Button>
        </div>
      );
    }
    return this.props.children;
  }
}

/** What one window shows. */
function WindowBody(props: { host: ColumnHost; win: DockWindow }) {
  const { host, win } = props;
  let content: ReactNode = null;
  if (win.kind === 'pending') {
    // The chat's stand-in: the page's own chat, as the Chat window draws it.
    content = (
      <div className="chat-theme">
        <Panel />
      </div>
    );
  } else {
    const backend = host.backends.get(win.id);
    content = backend ? <EmbeddedInterface backend={backend} /> : null;
  }
  return (
    <WindowBoundary name={win.title || win.iface}>{content}</WindowBoundary>
  );
}

function ghostText(drag: GroupDrag | null, group: string) {
  if (drag?.join === group) {
    return 'Release to stack here';
  }
  if (drag?.group === group && drag.float && !drag.window) {
    return 'Release to float';
  }
  return null;
}

function Group(props: {
  group: DockGroup;
  index: number;
  fill: boolean;
  host: ColumnHost;
  drag: GroupDrag | null;
  setDrag: (drag: GroupDrag | null) => void;
}) {
  const { group, index, fill, host, drag, setDrag } = props;
  const { windows } = host.state;
  const active = windows[group.active];
  const title = active?.title || active?.iface || '';
  const stacked = group.windows.length > 1;
  const dragged = drag?.group === group.id && !drag.window;
  const lit = drag?.join === group.id;
  const insert =
    !!drag?.window && !drag.float && !drag.join && drag.to === index;
  const offset = groupOffset(drag, group.id);
  const ghost = ghostText(drag, group.id);
  const toggle = () =>
    host.dispatch({
      type: 'collapse',
      group: group.id,
      collapsed: !group.collapsed,
    });
  return (
    <div
      className={[
        'column-group',
        group.collapsed && 'column-group--collapsed',
        fill && 'column-group--fill',
        dragged && 'column-group--dragged',
        dragged && drag?.float && 'column-group--floating',
        insert && 'column-group--insert',
      ]
        .filter(Boolean)
        .join(' ')}
      data-column-group={group.id}
      style={{
        transform: offset ? `translateY(${offset}px)` : undefined,
        height: group.collapsed || fill ? undefined : `${group.height}px`,
      }}
    >
      <div
        className={`column-head${lit ? ' column-head--lit' : ''}`}
        data-column-head={group.id}
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
            className="column-tabs"
            layout="scrollable"
            tabs={group.windows.map((id) => ({
              id,
              label: windows[id]?.title || windows[id]?.iface,
              selected: id === group.active,
            }))}
            onSelect={(id) => host.activate(id)}
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
          <span className="column-title">{title}</span>
        )}
        {canFloat(active) && (
          <>
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
          </>
        )}
      </div>
      {!group.collapsed && (
        <div className="column-body">
          {group.windows.map((id) => {
            const win = windows[id];
            if (!win) return null;
            // Every window of a stack stays mounted (its state survives a tab switch); only the active one shows.
            return (
              <div
                key={id}
                className="column-window"
                style={id === group.active ? undefined : { display: 'none' }}
              >
                <WindowBody host={host} win={win} />
              </div>
            );
          })}
          {ghost && <div className="column-body__ghost">{ghost}</div>}
          {!fill && (
            <div
              className="column-grip"
              onPointerDown={(event) => startResize(event, host, group)}
            />
          )}
        </div>
      )}
    </div>
  );
}

export function Column() {
  const host = columnHost;
  useSyncExternalStore(host.subscribe, host.getVersion);
  const [drag, setDrag] = useState<GroupDrag | null>(null);
  const { groups } = host.state;
  // The last expanded entry fills what the others leave.
  let fillAt = -1;
  groups.forEach((group, index) => {
    if (!group.collapsed) fillAt = index;
  });
  const insertEnd =
    !!drag?.window && !drag.float && !drag.join && drag.to >= groups.length;
  return (
    <div className={`column${drag ? ' column--dragging' : ''}`}>
      <MapSplitHandle />
      {groups.map((group, index) => (
        <Group
          key={group.id}
          group={group}
          index={index}
          fill={index === fillAt}
          host={host}
          drag={drag}
          setDrag={setDrag}
        />
      ))}
      {insertEnd && <div className="column-insert-end" />}
    </div>
  );
}
