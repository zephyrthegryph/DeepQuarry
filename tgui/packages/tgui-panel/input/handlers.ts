import { store } from '../events/store';
import { inputFocusRequestAtom } from './atoms';
import { isChannel } from './model';

/** The T/M hotkeys while the chat floats: focus the input row instead of opening the popup. */
export function focusInput(payload: { channel?: unknown } | undefined) {
  const channel = isChannel(payload?.channel) ? payload.channel : null;
  const previous = store.get(inputFocusRequestAtom);
  store.set(inputFocusRequestAtom, {
    channel,
    nonce: (previous?.nonce ?? 0) + 1,
  });
}
