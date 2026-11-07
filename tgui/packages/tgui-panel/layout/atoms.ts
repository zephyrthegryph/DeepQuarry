import { atom } from 'jotai';
import { type ChatMode, SHARE_DEFAULT } from './model';

/** Where the server has the chat pane (chat/layout); the skin starts at the bottom of the column. */
export const layoutModeAtom = atom<ChatMode>('bottom');

/** The share of the column the server holds for the pinned chat. */
export const layoutShareAtom = atom<number>(SHARE_DEFAULT);

/** The dock a drop would make right now, while the float window is dragged over the column. */
export type DockHint = { side: 'top' | 'bottom'; share: number };
export const dockHintAtom = atom<DockHint | null>(null);
