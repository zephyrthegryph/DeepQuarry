import { useAtomValue } from 'jotai';
import { useEffect, useRef, useState } from 'react';
import { Button } from 'tgui-core/components';
import { layoutModeAtom, layoutShareAtom } from './atoms';
import { measureShare, startWindowDrag, startWindowResize } from './geometry';
import { type ChatMode, pinRequest, shareMoved } from './model';

/** Asks the server to move the chat pane (layout/pin). */
export function requestMode(mode: ChatMode, via = 'button'): void {
  Byond.sendMessage('layout/pin', { mode, via });
}

/** Buttons in the tab row: swap the pinned side, or float / re-pin the chat. */
export function LayoutButtons() {
  const mode = useAtomValue(layoutModeAtom);
  if (mode === 'float') {
    return (
      <>
        <Button
          icon="arrow-up"
          tooltip="Pin to the top right"
          tooltipPosition="bottom-end"
          onClick={() => requestMode('top')}
        />
        <Button
          icon="arrow-down"
          tooltip="Pin to the bottom right"
          tooltipPosition="bottom-end"
          onClick={() => requestMode('bottom')}
        />
      </>
    );
  }
  return (
    <>
      <Button
        icon={mode === 'top' ? 'arrow-down' : 'arrow-up'}
        tooltip={
          mode === 'top'
            ? 'Move the chat to the bottom right'
            : 'Move the chat to the top right'
        }
        tooltipPosition="bottom-end"
        onClick={() => requestMode(pinRequest(mode, 'side'))}
      />
      <Button
        icon="window-restore"
        tooltip="Float the chat in its own window"
        tooltipPosition="bottom-end"
        onClick={() => requestMode(pinRequest(mode, 'float'))}
      />
    </>
  );
}

/** Parts of the tab row that keep their own clicks instead of starting a window drag. */
const NO_DRAG =
  'button, input, textarea, a, .Tabs__tab, .Button, [data-chat-input]';

/**
 * Drag handling for the floating window, which has no title bar at all: the
 * free space of the tab row moves it. Returns the pin the drag would make
 * (null when none) and the pointer handler for the row.
 */
export function useChatDrag() {
  const [hint, setHint] = useState<'top' | 'bottom' | null>(null);
  const onPointerDown = (event: React.PointerEvent<HTMLElement>) => {
    const target = event.target as HTMLElement;
    if (target.closest(NO_DRAG)) {
      return;
    }
    startWindowDrag(event, {
      onHint: setHint,
      onPin: (mode) => requestMode(mode, 'drop'),
    });
  };
  return { hint, onPointerDown };
}

/** Says what a drop would do, over the chat, while the window is dragged into the pin strip. */
export function ChatPinHint(props: { hint: 'top' | 'bottom' | null }) {
  if (!props.hint) {
    return null;
  }
  return (
    <div className="ChatPinHint">Release to pin to the {props.hint} right</div>
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
