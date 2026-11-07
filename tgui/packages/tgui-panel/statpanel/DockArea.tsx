/**
 * The window dock's frame in the stat panel (doc/rewrite/proposals/window_system.md):
 * one entry per group, its titlebar (or tabs for a stack), collapse, float and
 * close, a resize grip, and a placeholder the group's window is placed over
 * (dockHost.ts). A header drags: onto another header to stack its window there,
 * onto a gap to reorder (a stacked group's header splits its active tab out),
 * past the panel's left edge to float. Tabs reorder by dragging (ConsoleTabs).
 */
import {
  type PointerEvent as ReactPointerEvent,
  useState,
  useSyncExternalStore,
} from 'react';
import { ConsoleTabs } from 'tgui/components';
import { Button } from 'tgui-core/components';
import { type DockHost, dockHost } from './dockHost';
import type { DockGroup } from './windowDock';

/** How far the pointer moves before a press becomes a drag. */
const DRAG_START_PX = 6;
/** How far past the panel's left edge a drop floats the window. */
const FLOAT_PAST_PX = 14;

type Drag = { group: string; window: string; whole: boolean };
type Drop =
  | { kind: 'gap'; index: number }
  | { kind: 'head'; group: string; index: number }
  | { kind: 'float' }
  | null;

function dropAt(x: number, y: number): Drop {
  if (x < -FLOAT_PAST_PX) {
    return { kind: 'float' };
  }
  const node = document
    .elementFromPoint(x, y)
    ?.closest<HTMLElement>('[data-dock-drop]');
  if (!node) {
    return null;
  }
  const index = Number(node.dataset.index) || 0;
  if (node.dataset.dockDrop === 'gap') {
    return { kind: 'gap', index };
  }
  return { kind: 'head', group: node.dataset.group ?? '', index };
}

function finishDrop(host: DockHost, drag: Drag, drop: Drop) {
  if (!drop) {
    return;
  }
  if (drop.kind === 'float') {
    host.float(drag.window);
    return;
  }
  if (drop.kind === 'gap') {
    host.dispatch(
      drag.whole
        ? { type: 'moveGroup', group: drag.group, index: drop.index }
        : { type: 'splitWindow', id: drag.window, index: drop.index },
    );
    return;
  }
  if (drop.group && drop.group !== drag.group) {
    host.dispatch({
      type: 'moveWindow',
      id: drag.window,
      group: drop.group,
      index: drop.index,
    });
  } else if (drop.group === drag.group && !drag.whole) {
    host.dispatch({
      type: 'moveWindow',
      id: drag.window,
      group: drop.group,
      index: drop.index,
    });
  }
}

function startDrag(
  event: ReactPointerEvent<HTMLElement>,
  host: DockHost,
  drag: Drag,
  onHover: (drop: Drop) => void,
  onClick?: () => void,
) {
  if (
    event.button !== 0 ||
    (event.target as HTMLElement).closest?.('.Button')
  ) {
    return;
  }
  const target = event.currentTarget;
  const pointer = event.pointerId;
  const start = { x: event.clientX, y: event.clientY };
  let moving = false;
  target.setPointerCapture(pointer);
  const move = (e: PointerEvent) => {
    if (
      !moving &&
      Math.hypot(e.clientX - start.x, e.clientY - start.y) < DRAG_START_PX
    ) {
      return;
    }
    if (!moving) {
      moving = true;
      host.setDragging(true);
    }
    onHover(dropAt(e.clientX, e.clientY));
  };
  const end = (e: PointerEvent) => {
    target.removeEventListener('pointermove', move);
    target.removeEventListener('pointerup', end);
    target.removeEventListener('pointercancel', end);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
    onHover(null);
    if (moving) {
      const drop = e.type === 'pointerup' ? dropAt(e.clientX, e.clientY) : null;
      console.log('window dock: drop', { drag, drop });
      host.setDragging(false);
      finishDrop(host, drag, drop);
    } else {
      onClick?.();
    }
  };
  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
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

function Gap(props: { index: number; hover: Drop }) {
  const { index, hover } = props;
  const lit = hover?.kind === 'gap' && hover.index === index;
  return (
    <div
      className={`dock-gap${lit ? ' dock-gap--lit' : ''}`}
      data-dock-drop="gap"
      data-index={index}
    />
  );
}

function Group(props: {
  group: DockGroup;
  host: DockHost;
  hover: Drop;
  setHover: (drop: Drop) => void;
}) {
  const { group, host, hover, setHover } = props;
  const { windows } = host.state;
  const active = windows[group.active];
  const stacked = group.windows.length > 1;
  const lit = hover?.kind === 'head' && hover.group === group.id;
  const toggle = () =>
    host.dispatch({
      type: 'collapse',
      group: group.id,
      collapsed: !group.collapsed,
    });
  return (
    <div className="dock-group">
      <div
        className={`dock-head${lit ? ' dock-head--lit' : ''}`}
        data-dock-drop="head"
        data-group={group.id}
        data-index={group.windows.length}
        onPointerDown={(event) =>
          startDrag(
            event,
            host,
            { group: group.id, window: group.active, whole: !stacked },
            setHover,
          )
        }
        onDoubleClick={toggle}
      >
        <Button
          compact
          color="transparent"
          icon={group.collapsed ? 'chevron-right' : 'chevron-down'}
          tooltip={group.collapsed ? 'Expand' : 'Collapse'}
          onClick={toggle}
        />
        {stacked ? (
          <ConsoleTabs
            className="dock-tabs"
            layout="scrollable"
            tabs={group.windows.map((id) => ({
              id,
              label: windows[id]?.title || windows[id]?.iface,
              selected: id === group.active,
            }))}
            onSelect={(id) => host.dispatch({ type: 'activate', id })}
            onReorder={(next) => {
              const moved = next.find((id, i) => group.windows[i] !== id);
              if (moved) {
                host.dispatch({
                  type: 'moveWindow',
                  id: moved,
                  group: group.id,
                  index:
                    next.indexOf(moved) +
                    (next.indexOf(moved) > group.windows.indexOf(moved)
                      ? 1
                      : 0),
                });
              }
            }}
          />
        ) : (
          <span className="dock-title">{active?.title || active?.iface}</span>
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
              {active?.title || active?.iface}
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
  const [hover, setHover] = useState<Drop>(null);
  const { groups } = host.state;
  if (!groups.length) {
    return null;
  }
  return (
    <div
      className={`dock-area${host.dragging ? ' dock-area--dragging' : ''}`}
      ref={(node) => host.setArea(node)}
      onScroll={host.schedule}
    >
      {groups.map((group, index) => (
        <div key={group.id}>
          <Gap index={index} hover={hover} />
          <Group group={group} host={host} hover={hover} setHover={setHover} />
        </div>
      ))}
      <Gap index={groups.length} hover={hover} />
    </div>
  );
}
