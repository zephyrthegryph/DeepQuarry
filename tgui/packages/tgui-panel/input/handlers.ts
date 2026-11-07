import { store } from '../events/store';
import { inputFocusRequestAtom, radioOptionsAtom } from './atoms';
import { isChannel, type RadioOption } from './model';

/** The T/M hotkeys while the chat floats: focus the input row instead of opening the popup. */
export function focusInput(payload: { channel?: unknown } | undefined) {
  const channel = isChannel(payload?.channel) ? payload.channel : null;
  const previous = store.get(inputFocusRequestAtom);
  store.set(inputFocusRequestAtom, {
    channel,
    nonce: (previous?.nonce ?? 0) + 1,
  });
}

/** The server's department prefixes for what the speaker wears: rows with a key and a label, anything else is dropped. */
export function radioChannels(payload: { channels?: unknown } | undefined) {
  const rows: unknown[] = Array.isArray(payload?.channels)
    ? payload.channels
    : [];
  const options: RadioOption[] = [];
  for (const row of rows as { key?: unknown; label?: unknown }[]) {
    if (
      row &&
      typeof row.key === 'string' &&
      /^[:.]\S$/.test(row.key) &&
      typeof row.label === 'string'
    ) {
      options.push({ key: row.key, label: row.label });
    }
  }
  store.set(radioOptionsAtom, options);
}
