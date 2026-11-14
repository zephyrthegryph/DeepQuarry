/**
 * The right-hand column (doc/rewrite/proposals/window_system.md section 12):
 * one page, one window manager. Every window in it, the chat, the stat
 * panel's views and docked tgui interfaces, is an entry of the same list,
 * framed the same way and moved by the same code:
 * - an entry's header shows its title, or its tabs when windows are stacked;
 *   its chevron, a click on its name or a double click collapses it to the header;
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
  memo,
  type ReactNode,
  type PointerEvent as ReactPointerEvent,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from 'react';
import {
  DRAG_THRESHOLD,
  liveClamp,
  liveSlide,
  type OrderBox,
  Tabs,
} from 'tgui/dq';
import { ReloadBoundary } from 'tgui/ReloadBoundary';
import 'tgui/embeddedStyles';
import { floatSize, type Pair, TITLE_GRAB } from 'tgui/floatPlacement';
import { EmbeddedInterface } from 'tgui/routes';
import { Button } from 'tgui-core/components';
import { MapSplitHandle } from '../layout/ChatLayout';
import { POP_OUT_DISTANCE } from '../layout/model';
import { Panel } from '../Panel';
import { FloatFollow } from './floatDrag';
import { type ColumnHost, columnHost, sendPage } from './host';
import {
  type DockGroup,
  type DockWindow,
  dropIndex,
  fillHeight,
  fitHeights,
} from './model';

/** Presses here keep their own meaning (buttons click, tabs select and re-arrange). */
const NO_DRAG = 'button, input, .Button, .Tab, [data-dq-tab]';

/** The entry's name: a click on it folds the entry. */
const NAME = '.column-title';

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

/** Whether two drag states draw the same list (the boxes are measured once per drag). */
export function sameDrag(a: GroupDrag | null, b: GroupDrag | null): boolean {
  return (
    !!a &&
    !!b &&
    a.group === b.group &&
    a.window === b.window &&
    a.dy === b.dy &&
    a.to === b.to &&
    a.join === b.join &&
    a.float === b.float
  );
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

/** Whether a window can be dragged out of the page to float: the server's floatable word and the column never being empty (host.mayLeave()), whatever buttons its header shows. */
export const canFloat = (host: ColumnHost, id?: string) =>
  !!id && host.mayLeave(id);

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

/** The float button: the window leaves the column at the size its entry had, so a pop out keeps what the player sized. */
function floatEntry(host: ColumnHost, group: DockGroup) {
  const rect = document
    .querySelector<HTMLElement>(`[data-column-group="${group.id}"]`)
    ?.getBoundingClientRect();
  if (!rect) {
    host.float(group.active);
    return;
  }
  const ratio = window.devicePixelRatio || 1;
  const size = floatSize({ w: rect.width, h: rect.height }, ratio, [
    window.screen.width * ratio,
    window.screen.height * ratio,
  ]);
  // It opens where the entry was (the title bar's middle at the entry's top), as tall and wide as the entry was.
  const point = {
    x: Math.round((window.screenX + rect.left + rect.width / 2) * ratio),
    y: Math.round((window.screenY + rect.top) * ratio + TITLE_GRAB),
  };
  host.float(group.active, point, { x: size[0], y: size[1] });
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
    ? canFloat(host, pulled)
    : !!groupOf?.windows.every((id) => canFloat(host, id)) &&
      // A whole entry floats only when another entry stays: the column is never empty.
      host.state.groups.length > 1;
  let live: GroupDrag | null = null;
  // Set once the drag left the page with the button still down: the window is floated and follows the pointer from here.
  let follow: FloatFollow | null = null;
  // What the list was last told: it redraws only when the drag's derived state changed, and at most once a frame.
  let shown: GroupDrag | null = null;
  let frame = 0;
  const publish = () => {
    frame = 0;
    if (live && !sameDrag(shown, live)) {
      shown = live;
      setDrag(live);
    }
  };
  const startFloat = (e: PointerEvent) => {
    const node = document.querySelector<HTMLElement>(
      `[data-column-group="${group}"]`,
    );
    const rect = node?.getBoundingClientRect();
    const ratio = window.devicePixelRatio || 1;
    const size = floatSize(
      { w: rect?.width ?? 0, h: rect?.height ?? 0 },
      ratio,
      [window.screen.width * ratio, window.screen.height * ratio],
    );
    const point = screenPoint(e);
    const at: Pair = [point.x, point.y];
    host.trace('drag left the column: floating live', {
      group,
      pulled,
      point: at,
      size,
      docked: rect && [rect.width, rect.height],
      ratio,
    });
    const made = new FloatFollow(
      size,
      at,
      (id, props) => Byond.winset(id, props),
      (message, detail) => host.trace(message, detail),
      (id) => {
        if (host.following === made) host.following = null;
        sendPage('WM-FloatDone', { window: id });
      },
    );
    follow = made;
    host.following = made;
    const sized = { x: size[0], y: size[1] };
    let floated = false;
    if (pulled) {
      floated = host.float(pulled, point, sized);
    } else {
      const now = host.state.groups.find((g) => g.id === group);
      for (const id of now?.windows ?? []) {
        const active = id === now?.active;
        floated =
          host.float(id, active ? point : null, active ? sized : null) ||
          floated;
      }
    }
    if (!floated) {
      follow = null;
      host.following = null;
      return false;
    }
    // The entry leaves the page: keep the pointer on the document so the drag goes on after its header is gone.
    try {
      document.body.setPointerCapture(pointer);
    } catch {
      // Events still reach the document while the button is down.
    }
    setDrag(null);
    return true;
  };
  // The pop-out opens a native window that takes the focus, and the page can lose the pointer to it (a pointercancel, or a new pointer id
  // for the same press). The drag is not over then: the window keeps following while the button is down, and is only released by the
  // button going up, the button found up on a move, or no event for a grace period after the cancel.
  let grace: ReturnType<typeof setTimeout> | undefined;
  const mine = (e: PointerEvent) => e.pointerId === pointer || !!follow;
  const move = (e: PointerEvent) => {
    if (!mine(e)) return;
    if (follow) {
      clearTimeout(grace);
      if (e.buttons === 0 && e.type !== 'pointerup') {
        host.trace('drag found the button up while floated', { type: e.type });
        end(e);
        return;
      }
      const point = screenPoint(e);
      follow.move([point.x, point.y]);
      return;
    }
    const box = boxes.find((b) => b.id === group);
    const dy =
      !pulled && box ? liveClamp(box, e.clientY - start.y, min, max) : 0;
    const float =
      floatable &&
      outOfPage(e.clientX, e.clientY, window.innerWidth, window.innerHeight);
    const join = float ? null : headUnder(e.clientX, e.clientY, group);
    if (float && startFloat(e)) return;
    live = {
      group,
      window: pulled,
      dy,
      to: pulled ? indexAtY(boxes, e.clientY) : dropIndex(boxes, group, dy),
      join,
      float,
      boxes,
    };
    if (!frame) frame = requestAnimationFrame(publish);
  };
  const end = (e: PointerEvent) => {
    if (!mine(e)) return;
    if (follow && e.type === 'pointercancel') {
      const point = screenPoint(e);
      host.trace('drag lost the pointer while floated: still following', {
        point,
      });
      clearTimeout(grace);
      grace = setTimeout(() => end(new PointerEvent('pointerup', e)), 1500);
      return;
    }
    clearTimeout(grace);
    document.removeEventListener('pointermove', move);
    document.removeEventListener('pointerup', end);
    document.removeEventListener('pointercancel', end);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
    if (document.body.hasPointerCapture(pointer)) {
      document.body.releasePointerCapture(pointer);
    }
    const done = live;
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    setDrag(null);
    if (follow) {
      const point = screenPoint(e);
      host.trace('drag ended while floated', { type: e.type, point });
      follow.release([point.x, point.y]);
      return;
    }
    if (e.type !== 'pointerup') {
      host.trace('drag cancelled', { group, pulled });
    }
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
    // The entry as it is now: windows may have closed, or the page reloaded, while the pointer was down.
    const now = host.state.groups.find((g) => g.id === group);
    if (!now) {
      return;
    }
    if (done.float) {
      for (const id of now.windows) {
        host.float(id, id === now.active ? screenPoint(e) : null);
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
  clickName: () => void,
) {
  if (event.button !== 0 || (event.target as HTMLElement).closest?.(NO_DRAG)) {
    return;
  }
  const target = event.currentTarget;
  const pointer = event.pointerId;
  const start = { x: event.clientX, y: event.clientY };
  // A press that never became a drag, on the name, is a click on the name.
  const onName = !!(event.target as HTMLElement).closest?.(NAME);
  const stop = () => {
    document.removeEventListener('pointermove', wait);
    document.removeEventListener('pointerup', up);
    document.removeEventListener('pointercancel', stop);
  };
  const up = (e: PointerEvent) => {
    if (e.pointerId !== pointer) return;
    stop();
    if (onName) clickName();
  };
  const wait = (e: PointerEvent) => {
    if (e.pointerId !== pointer) return;
    if (Math.hypot(e.clientX - start.x, e.clientY - start.y) < DRAG_THRESHOLD)
      return;
    stop();
    runDrag(target, pointer, start, host, group.id, null, setDrag, e);
  };
  document.addEventListener('pointermove', wait);
  document.addEventListener('pointerup', up);
  document.addEventListener('pointercancel', stop);
}

/** An entry's drawn height (its frame, as the model counts it), or `fallback` when it is not on the page. */
function drawnHeight(id: string, fallback: number): number {
  const rect = document
    .querySelector<HTMLElement>(`[data-column-group="${id}"]`)
    ?.getBoundingClientRect();
  return rect ? Math.round(rect.height) : fallback;
}

function startResize(
  event: ReactPointerEvent<HTMLElement>,
  host: ColumnHost,
  group: DockGroup,
  below: string | null,
) {
  if (event.button !== 0) {
    return;
  }
  event.stopPropagation();
  const target = event.currentTarget;
  const pointer = event.pointerId;
  const startY = event.clientY;
  const startHeight = drawnHeight(group.id, group.height);
  const nextStart = below ? drawnHeight(below, 0) : 0;
  target.setPointerCapture(pointer);
  // The whole column redraws on each resize: at most once a frame, and the last height is always applied.
  let dy = 0;
  let frame = 0;
  const apply = () => {
    frame = 0;
    host.dispatch({
      type: 'boundary',
      group: group.id,
      next: below,
      start: startHeight,
      nextStart,
      dy,
    });
  };
  const move = (e: PointerEvent) => {
    dy = e.clientY - startY;
    if (!frame) frame = requestAnimationFrame(apply);
  };
  const end = () => {
    if (frame) {
      cancelAnimationFrame(frame);
      apply();
    }
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

/** What one window shows. */
const WindowBody = memo(function WindowBody(props: {
  host: ColumnHost;
  win: DockWindow;
}) {
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
    <ReloadBoundary name={win.title || win.iface}>{content}</ReloadBoundary>
  );
});

function ghostText(drag: GroupDrag | null, group: string) {
  if (drag?.join === group) {
    return 'Release to stack here';
  }
  if (drag?.group === group && drag.float && !drag.window) {
    return 'Release to float';
  }
  return null;
}

/** What a live drag means for one entry: plain values, so an entry the drag does not touch gets the same props and is not redrawn. */
function dragView(drag: GroupDrag | null, group: string, index: number) {
  return {
    dragged: drag?.group === group && !drag.window,
    floating: drag?.group === group && !drag.window && drag.float,
    lit: drag?.join === group,
    insert: !!drag?.window && !drag.float && !drag.join && drag.to === index,
    offset: groupOffset(drag, group),
    ghost: ghostText(drag, group),
  };
}

const Group = memo(function Group(
  props: {
    group: DockGroup;
    index: number;
    fill: boolean;
    /** The expanded, non-filling entry under this one: the grip's other side (null: the chat, or nothing). */
    below: string | null;
    /** The height it is drawn at (fitHeights()): its own, or less on a column too short for every entry. */
    height: number;
    host: ColumnHost;
    /** The host's version: an entry redraws for a change of the column, not for a drag that does not touch it. */
    version: number;
    setDrag: (drag: GroupDrag | null) => void;
  } & ReturnType<typeof dragView>,
) {
  const {
    group,
    fill,
    below,
    height,
    host,
    setDrag,
    dragged,
    floating,
    lit,
    insert,
    offset,
    ghost,
  } = props;
  const { windows } = host.state;
  // Scroll positions inside the entry: a reorder moves its DOM node, which resets every scroller in it, so each is put back after a render.
  const scrolls = useRef(new Map<Element, [number, number]>());
  useLayoutEffect(() => {
    for (const [node, [top, left]] of scrolls.current) {
      if (!node.isConnected) scrolls.current.delete(node);
      else if (node.scrollTop !== top || node.scrollLeft !== left) {
        node.scrollTop = top;
        node.scrollLeft = left;
      }
    }
  });
  const active = windows[group.active];
  const title = active?.title || active?.iface || '';
  const stacked = group.windows.length > 1;
  const foldable = host.mayCollapse(group);
  const collapsed = host.collapsed(group);
  const toggle = () => {
    if (!foldable) return;
    host.dispatch({
      type: 'collapse',
      group: group.id,
      collapsed: !collapsed,
    });
  };
  return (
    <div
      className={[
        'column-group',
        collapsed && 'column-group--collapsed',
        fill && 'column-group--fill',
        dragged && 'column-group--dragged',
        dragged && floating && 'column-group--floating',
        insert && 'column-group--insert',
      ]
        .filter(Boolean)
        .join(' ')}
      data-column-group={group.id}
      onScrollCapture={(event) => {
        const node = event.target as Element;
        scrolls.current.set(node, [node.scrollTop, node.scrollLeft]);
      }}
      style={{
        transform: offset ? `translateY(${offset}px)` : undefined,
        height: collapsed || fill ? undefined : `${height}px`,
        // The filling entry the player sized keeps that height (the column scrolls) instead of only what the others leave.
        minHeight: fill && !collapsed ? `${fillHeight(group)}px` : undefined,
      }}
    >
      <div
        className={`column-head${lit ? ' column-head--lit' : ''}`}
        data-column-head={group.id}
        onPointerDown={(event) =>
          pressHead(event, host, group, setDrag, toggle)
        }
        onDoubleClick={(event) => {
          const on = event.target as HTMLElement;
          if (!on.closest(NO_DRAG) && !on.closest(NAME)) toggle();
        }}
      >
        {foldable && (
          <Button
            compact
            color="transparent"
            icon={collapsed ? 'chevron-right' : 'chevron-down'}
            tooltip={collapsed ? 'Expand' : 'Collapse'}
            onClick={toggle}
          />
        )}
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
        {host.hasWindowButtons(group.active) && (
          <>
            <Button
              compact
              color="transparent"
              icon="up-right-from-square"
              tooltip="Float"
              onClick={() => floatEntry(host, group)}
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
      {!collapsed && (
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
          <div
            className={`column-grip${fill ? ' column-grip--fill' : ''}`}
            onPointerDown={(event) => startResize(event, host, group, below)}
          />
        </div>
      )}
    </div>
  );
});

/** The expanded entry after `index` when it is not the filling one: the grip's neighbour that gives and takes space. */
function belowOf(
  groups: DockGroup[],
  index: number,
  fillAt: number,
  host: ColumnHost,
): string | null {
  for (let i = index + 1; i < groups.length; i++) {
    if (host.collapsed(groups[i])) continue;
    return i === fillAt ? null : groups[i].id;
  }
  return null;
}

export function Column() {
  const host = columnHost;
  const version = useSyncExternalStore(host.subscribe, host.getVersion);
  const [drag, setDrag] = useState<GroupDrag | null>(null);
  const { groups } = host.state;
  // The last expanded entry fills what the others leave.
  let fillAt = -1;
  groups.forEach((group, index) => {
    if (!host.collapsed(group)) fillAt = index;
  });
  const insertEnd =
    !!drag?.window && !drag.float && !drag.join && drag.to >= groups.length;
  // The page's height: a resize of the column (or of the client) fits the entries again.
  const [pageHeight, setPageHeight] = useState(() => window.innerHeight);
  useEffect(() => {
    const resized = () => setPageHeight(window.innerHeight);
    window.addEventListener('resize', resized);
    return () => window.removeEventListener('resize', resized);
  }, []);
  const heights = fitHeights(groups, fillAt, pageHeight);
  return (
    <div className={`column${drag ? ' column--dragging' : ''}`}>
      <MapSplitHandle />
      {groups.map((group, index) => (
        <Group
          key={group.id}
          group={group}
          index={index}
          fill={index === fillAt}
          below={belowOf(groups, index, fillAt, host)}
          height={heights[index]}
          host={host}
          version={version}
          setDrag={setDrag}
          {...dragView(drag, group.id, index)}
        />
      ))}
      {insertEnd && <div className="column-insert-end" />}
    </div>
  );
}
