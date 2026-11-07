import { atom } from 'jotai';
import type { InputChannel, RadioOption } from './model';

/** The server asked for the input row to take focus, in a channel (chat/focusInput). */
export const inputFocusRequestAtom = atom<{
  channel: InputChannel | null;
  nonce: number;
} | null>(null);

/** The department prefixes the speaker's radios offer (chat/radioChannels). */
export const radioOptionsAtom = atom<RadioOption[]>([]);
