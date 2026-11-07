import { store } from '../events/store';
import { dragHandlers } from './actions';
import { layoutModeAtom, layoutShareAtom } from './atoms';
import { clampFloatToMain, resumePopoutDrag } from './geometry';
import { clampShare, isMode } from './model';

/** The server moved the chat pane, or told which layout it is in (chat/layout). */
export function chatLayout(
  payload: { mode?: unknown; share?: unknown } | undefined,
) {
  if (isMode(payload?.mode)) {
    const was = store.get(layoutModeAtom);
    store.set(layoutModeAtom, payload.mode);
    if (payload.mode === 'float') {
      clampFloatToMain();
      if (was !== 'float') {
        // A pop-out drag carries on in the window the pane just moved to.
        resumePopoutDrag(dragHandlers);
      }
    }
  }
  if (typeof payload?.share === 'number') {
    store.set(layoutShareAtom, clampShare(payload.share));
  }
}
