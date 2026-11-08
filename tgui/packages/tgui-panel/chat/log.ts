/**
 * Where the stored chat log stands in the server's history, so a chat window
 * that moves (docked, floating, docked again) or a page that reloads loses
 * nothing and shows nothing twice (tgui/interfaces/Chat.tsx).
 *
 * Whichever page shows the chat saves the log, and with it a mark: the
 * connection it came from (`session`, from the server's Chat data) and the
 * sequence number of the last message it holds. A chat window first loads
 * the stored log; when the mark is from this connection, the server replays
 * only what follows it (chat/ready, SSchat.replay), else everything it kept.
 * A page whose own chat is behind the stored log (the column page after the
 * chat floated a while) loads the stored log again before asking.
 */
import { storage } from 'common/storage';
import { lastShownSequence, markShownThrough } from './handlers';

export type LogMark = { session: string; sequence: number };

const MARK_KEY = 'chat-mark';
/** How long a chat window waits for the stored log before it asks the server anyway: storage that never answers must not stall it. */
export const LOG_WAIT_MS = 2000;

function within<T>(promise: Promise<T>, fallback: T): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((resolve) =>
      setTimeout(() => resolve(fallback), LOG_WAIT_MS),
    ),
  ]);
}

let session = '';
let loader: (() => Promise<void>) | null = null;
let loaded: Promise<void> | null = null;
let notifyLoaded: (() => void) | null = null;

/** This connection's id (the server's Chat data); marks from another connection mean nothing to its history. */
export function setChatSession(id: string): void {
  session = id;
}

export function chatSession(): string {
  return session;
}

/** The persistence hook's loader of the stored log (use-chat-persistence.ts). */
export function registerLogLoader(load: () => Promise<void>): void {
  loader = load;
}

let claimed = false;

/** True the first time only: a page loads the stored log once by itself (a chat that docks again remounts). */
export function claimLogLoad(): boolean {
  if (claimed) return false;
  claimed = true;
  return true;
}

/** Called once when this page's stored log is in. */
export function logLoadedNow(): void {
  if (!loaded) loaded = Promise.resolve();
  notifyLoaded?.();
  notifyLoaded = null;
}

/** Resolves when this page's stored log is in. */
export function whenLogLoaded(): Promise<void> {
  if (!loaded) {
    loaded = new Promise((resolve) => {
      notifyLoaded = resolve;
    });
  }
  return loaded;
}

/** Saves the mark with the log: called where the log is saved. */
export function saveLogMark(): void {
  const sequence = lastShownSequence();
  if (!session || sequence === null) return;
  storage.set(MARK_KEY, { session, sequence } satisfies LogMark);
}

/** The stored mark's sequence when it is this connection's, else null. */
export async function storedSequence(): Promise<number | null> {
  const mark = (await storage.get(MARK_KEY)) as LogMark | null;
  if (!mark || !session || mark.session !== session) return null;
  return typeof mark.sequence === 'number' ? mark.sequence : null;
}

/**
 * What a chat window asks the server for: everything after this number. A
 * page behind the stored log loads it again first (clear(): its own lines
 * go, the stored ones come back), so the stored log and the replay meet
 * exactly at the mark.
 */
export async function chatResumeAfter(clear: () => void): Promise<number> {
  await within(whenLogLoaded(), undefined);
  const stored = await within(storedSequence(), null);
  const shown = lastShownSequence();
  if (stored === null) return shown ?? -1;
  if (shown !== null && shown >= stored) return shown;
  if (shown !== null && loader) {
    clear();
    await loader();
  }
  markShownThrough(stored);
  return stored;
}
