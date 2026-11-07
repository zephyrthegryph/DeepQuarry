import { useAtomValue } from 'jotai';
import { useEffect, useRef, useState } from 'react';
import { Button } from 'tgui-core/components';
import { layoutModeAtom, layoutShareAtom } from './atoms';
import { measureShare, startWindowDrag, startWindowResize } from './geometry';
import { type ChatMode, pinRequest, shareMoved } from './model';

/** Asks the server to move the chat pane (layout/pin). */
export function requestMode(mode: ChatMode): void {
  Byond.sendMessage('layout/pin', { mode });
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

/** The strip that moves the floating window (it has no OS title bar). */
export function ChatHeader() {
  const [hint, setHint] = useState<'top' | 'bottom' | null>(null);
  return (
    <div
      className="ChatHeader"
      onPointerDown={(event) =>
        startWindowDrag(event, { onHint: setHint, onPin: requestMode })
      }
    >
      <span className="ChatHeader__title">
        {hint
          ? `Release to pin to the ${hint} right`
          : 'CHAT - drag to move, drop at the right edge to pin'}
      </span>
    </div>
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
