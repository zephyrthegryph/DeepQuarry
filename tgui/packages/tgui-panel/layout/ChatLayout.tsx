import { useAtomValue } from 'jotai';
import { useEffect, useRef } from 'react';
import { dragHandlers, requestMode } from './actions';
import { dockHintAtom, layoutModeAtom, layoutShareAtom } from './atoms';
import {
  measureMapSplit,
  measureShare,
  startDockedDrag,
  startSplitDrag,
  startWindowDrag,
  startWindowResize,
} from './geometry';
import { type ResizeEdges, shareMoved } from './model';

/** Parts of the tab row that keep their own clicks instead of starting a window drag. */
const NO_DRAG =
  'button, input, textarea, a, .Tabs__tab, .Button, [data-chat-input]';

/**
 * Drag handling for the tab row. A floating chat has no title bar: the free
 * space of the row moves it, and dropping it over the main window's right
 * column docks it there (the hint says where). A docked chat dragged by the
 * row pops out into a window under the pointer. Returns the dock the drag
 * would make (null when none) and the pointer handler for the row.
 */
export function useChatDrag() {
  const floating = useAtomValue(layoutModeAtom) === 'float';
  const hint = useAtomValue(dockHintAtom);
  const onPointerDown = (event: React.PointerEvent<HTMLElement>) => {
    const target = event.target as HTMLElement;
    if (target.closest(NO_DRAG)) {
      return;
    }
    if (!floating) {
      startDockedDrag(event, (at) => requestMode('float', 'popout', at));
      return;
    }
    startWindowDrag(event, dragHandlers);
  };
  return { hint, onPointerDown };
}

/** Says what a drop would do, over the chat, while the window is dragged over the column. */
export function ChatPinHint(props: {
  hint: { side: 'top' | 'bottom'; share: number } | null;
}) {
  if (!props.hint) {
    return null;
  }
  return (
    <div className="ChatPinHint">
      Release to dock at the {props.hint.side} right ({props.hint.share}% of the
      column)
    </div>
  );
}

/** Every edge and corner of the floating window resizes it (the window has no OS frame, so the page draws the handles). */
const RESIZE_HANDLES: { name: string; edges: ResizeEdges }[] = [
  { name: 'n', edges: { top: true } },
  { name: 's', edges: { bottom: true } },
  { name: 'w', edges: { left: true } },
  { name: 'e', edges: { right: true } },
  { name: 'nw', edges: { top: true, left: true } },
  { name: 'ne', edges: { top: true, right: true } },
  { name: 'sw', edges: { bottom: true, left: true } },
  { name: 'se', edges: { bottom: true, right: true } },
];

export function ChatResizeHandles() {
  return (
    <>
      {RESIZE_HANDLES.map((handle) => (
        <div
          key={handle.name}
          className={`ChatResizeHandle ChatResizeHandle--${handle.name}`}
          onPointerDown={(event) => startWindowResize(event, handle.edges)}
        />
      ))}
    </>
  );
}

/**
 * Live splitter handles on the docked chat: its edge toward the stat panel
 * moves the chat/stat split, its left edge moves the map/column split. Both
 * update while dragging (BYOND's own splitter only applies on release).
 */
export function ChatSplitHandles() {
  const mode = useAtomValue(layoutModeAtom);
  if (mode === 'float') {
    return null;
  }
  return (
    <>
      <div
        className={`ChatSplitHandle ChatSplitHandle--${mode === 'top' ? 'bottom' : 'top'}`}
        onPointerDown={(event) =>
          startSplitDrag(event, 'column', mode, (share) =>
            Byond.sendMessage('layout/share', { share }),
          )
        }
      />
      <MapSplitHandle />
    </>
  );
}

/** The left edge of a column page: drags the map/column split live. */
export function MapSplitHandle() {
  return (
    <div
      className="ChatSplitHandle ChatSplitHandle--left"
      onPointerDown={(event) =>
        startSplitDrag(event, 'map', 'bottom', (split) =>
          Byond.sendMessage('layout/mapsplit', { split }),
        )
      }
    />
  );
}

/**
 * Reports the share of the column when the player drags the splitter (the
 * panel is resized): measured a moment after the last resize, only while pinned.
 */
export function useShareReport(): void {
  const mode = useAtomValue(layoutModeAtom);
  const share = useAtomValue(layoutShareAtom);
  const known = useRef(share);
  const lastSplit = useRef<number | null>(null);
  known.current = share;
  useEffect(() => {
    if (mode === 'float') {
      return;
    }
    let timer: ReturnType<typeof setTimeout> | undefined;
    const onResize = () => {
      clearTimeout(timer);
      timer = setTimeout(async () => {
        const measured = await measureShare();
        if (measured !== null && shareMoved(known.current, measured)) {
          Byond.sendMessage('layout/share', { share: measured });
        }
        const split = await measureMapSplit();
        if (split !== null && split !== lastSplit.current) {
          lastSplit.current = split;
          console.log('chat layout: map split measured', { split });
          Byond.sendMessage('layout/mapsplit', { split });
        }
      }, 700);
    };
    window.addEventListener('resize', onResize);
    return () => {
      clearTimeout(timer);
      window.removeEventListener('resize', onResize);
    };
  }, [mode]);
}
