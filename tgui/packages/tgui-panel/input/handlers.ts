import { store } from '../events/store';
import type { LanguageRules } from 'tgui/dq';
import {
  inputFocusRequestAtom,
  languageRulesAtom,
  previewEnabledAtom,
  radioOptionsAtom,
} from './atoms';
import { isChannel, type RadioOption } from './model';

/** A speech hotkey (T, 5, 6, Y, F2, ...): focus the input row in that channel. */
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

/** The speaker's rules for the live preview, and whether the preview is on. */
export function languageRules(
  payload: { rules?: LanguageRules; preview?: unknown } | undefined,
) {
  store.set(languageRulesAtom, payload?.rules ?? null);
  store.set(previewEnabledAtom, payload?.preview !== false && payload?.preview !== 0);
}
