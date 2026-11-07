import { atom } from 'jotai';
import { type ChatMode, SHARE_DEFAULT } from './model';

/** Where the server has the chat pane (chat/layout); the skin starts at the bottom of the column. */
export const layoutModeAtom = atom<ChatMode>('bottom');

/** The share of the column the server holds for the pinned chat. */
export const layoutShareAtom = atom<number>(SHARE_DEFAULT);
