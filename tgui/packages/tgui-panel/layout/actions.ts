import { store } from '../events/store';
import { dockHintAtom } from './atoms';
import type { DragHandlers } from './geometry';
import type { ChatMode } from './model';

/** The float window is drawn this see-through (0-255) while a dock preview shows, so the preview in the column reads through it. */
export const PREVIEW_ALPHA = 140;

/** Asks the server to move the chat pane (layout/pin). */
export function requestMode(
  mode: ChatMode,
  via = 'drop',
  at?: { x: number; y: number },
  share?: number,
): void {
  Byond.sendMessage('layout/pin', { mode, via, at, share });
}

/**
 * Shows or clears the dock preview: the hint text in the chat, the target
 * area outlined in the stat panel (layout/preview, relayed by the server), and
 * the float window made see-through so the outline shows under it.
 */
export function setDockHint(side: 'top' | 'bottom' | null, share = 0): void {
  store.set(dockHintAtom, side ? { side, share } : null);
  Byond.sendMessage('layout/preview', { side, share });
  Byond.winset('chat_float', 'alpha', `${side ? PREVIEW_ALPHA : 255}`);
  console.log('chat layout: dock preview', { side, share });
}

/** What a window drag does with its hint and its drop. */
export const dragHandlers: DragHandlers = {
  onHint: (side, share) => setDockHint(side, share),
  onPin: (mode, share) => requestMode(mode, 'drop', undefined, share),
};
