/**
 * Where the chat was scrolled, kept across a pop out or pop in. Docked, the chat is part of the column page and survives in its memory
 * (the renderer keeps every message); floating, it is a page of its own that starts from the client's storage. What is kept is the
 * position and whether the chat was pinned to the newest line: a pinned chat reopens at the bottom, whatever height the log has there.
 */
import { storage } from 'common/storage';

export type ChatScroll = { top: number; tracking: boolean };

const KEY = 'chat-scroll';
const SAVE_DELAY_MS = 150;

let memory: ChatScroll | null = null;
let timer: ReturnType<typeof setTimeout> | undefined;

export function rememberChatScroll(state: ChatScroll): void {
  memory = {
    top: Math.max(0, Math.round(state.top)),
    tracking: state.tracking,
  };
  clearTimeout(timer);
  timer = setTimeout(() => {
    storage.set(KEY, memory);
  }, SAVE_DELAY_MS);
}

/** The state last remembered in this page, else the one in the client's storage, else null. */
export async function recallChatScroll(): Promise<ChatScroll | null> {
  if (memory) return memory;
  try {
    const stored = await storage.get(KEY);
    if (
      stored &&
      typeof stored.top === 'number' &&
      typeof stored.tracking === 'boolean'
    ) {
      return memory ?? { top: stored.top, tracking: stored.tracking };
    }
  } catch {
    // Nothing kept: the chat opens at the newest line.
  }
  return null;
}

/** For tests: forgets the page's memory. */
export function forgetChatScroll(): void {
  memory = null;
  clearTimeout(timer);
}
