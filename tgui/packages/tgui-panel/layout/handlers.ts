import { store } from '../events/store';
import { layoutModeAtom, layoutShareAtom } from './atoms';
import { clampShare, isMode } from './model';

/** The server moved the chat pane, or told which layout it is in (chat/layout). */
export function chatLayout(payload: { mode?: unknown; share?: unknown } | undefined) {
  if (isMode(payload?.mode)) {
    store.set(layoutModeAtom, payload.mode);
  }
  if (typeof payload?.share === 'number') {
    store.set(layoutShareAtom, clampShare(payload.share));
  }
}
