import { useAtomValue } from 'jotai';
import { useEffect, useRef, useState } from 'react';
import { layoutModeAtom, layoutShareAtom } from './atoms';
import {
  measureShare,
  startDockedDrag,
  startWindowDrag,
  startWindowResize,
} from './geometry';
import { type ChatMode, shareMoved } from './model';

/** Asks the server to move the chat pane (layout/pin). */
export function requestMode(
  mode: ChatMode,
  via = 'drop',
  at?: { x: number; y: number },
): void {
  Byond.sendMessage('layout/pin', { mode, via, at });
}

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
  const [hint, setHint] = useState<'top' | 'bottom' | null>(null);
  const onPointerDown = (event: React.PointerEvent<HTMLElement>) => {
    const target = event.target as HTMLElement;
    if (target.closest(NO_DRAG)) {
      return;
    }
    if (!floating) {
      startDockedDrag(event, (at) => requestMode('float', 'popout', at));
      return;
    }
    startWindowDrag(event, {
      onHint: setHint,
      onPin: (mode) => requestMode(mode, 'drop'),
    });
  };
  return { hint, onPointerDown };
}

/** Says what a drop would do, over the chat, while the window is dragged over the column. */
export function ChatPinHint(props: { hint: 'top' | 'bottom' | null }) {
  if (!props.hint) {
    return null;
  }
  return (
    <div className="ChatPinHint">Release to dock at the {props.hint} right</div>
  );
}

/** The corner that resizes the floating window. */
export function ChatResizeGrip() {
  return (
    <div
      className="ChatResizeGrip"
      title="Resize"
      onPointerDown={startWindowResize}
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
      }, 700);
    };
    window.addEventListener('resize', onResize);
    return () => {
      clearTimeout(timer);
      window.removeEventListener('resize', onResize);
    };
  }, [mode]);
}
