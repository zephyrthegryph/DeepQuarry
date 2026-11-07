import { atom } from 'jotai';
import type { LanguageRules } from 'tgui/dq';
import type { InputChannel, RadioOption } from './model';

/** The server asked for the input row to take focus, in a channel (chat/focusInput). */
export const inputFocusRequestAtom = atom<{
  channel: InputChannel | null;
  nonce: number;
} | null>(null);

/** The department prefixes the speaker's radios offer (chat/radioChannels). */
export const radioOptionsAtom = atom<RadioOption[]>([]);

/** The speaker's language and formatting rules for the live preview (chat/languageRules), sent when the row opens. */
export const languageRulesAtom = atom<LanguageRules | null>(null);

/** Whether the live preview shows (sent with the rules; always on today). */
export const previewEnabledAtom = atom(true);
