import { focusMap } from '../../focus';
import { logger } from '../../logging';
import { suspendRenderer } from '../../renderer';
import { resetReveal } from '../../reveal';
import {
  configAtom,
  resetStore,
  store,
  suspendedAtom,
  suspendingAtom,
} from '../store';

/// --------- Handlers ------------------------------------------------------///

let suspendInterval: NodeJS.Timeout | null = null;

/** Resets all state and refocuses byond window */
export function suspend(): void {
  suspendRenderer();
  resetStore();
  // Release the reveal claim: a pooled window may be reused for a different
  // interface next open, which might rely on the route-level fallback reveal.
  resetReveal();

  if (suspendInterval) clearInterval(suspendInterval);

  store.set(configAtom, (prev) => ({
    ...prev,
    title: '',
    status: 1,
  }));
  store.set(suspendingAtom, false);
  store.set(suspendedAtom, Date.now());

  Byond.winset(Byond.windowId, {
    'is-visible': false,
  });

  focusMap();
}

/// --------- Helpers -------------------------------------------------------///

const TWO_SECONDS = 2000;

function suspendMsg(): void {
  Byond.sendMessage('suspend');
}

/** Signals Byond to dismiss the window */
export function suspendStart(): void {
  if (suspendInterval) clearInterval(suspendInterval);

  store.set(suspendingAtom, true);

  logger.log(`suspending (${Byond.windowId})`);
  suspendMsg();
  suspendInterval = setInterval(suspendMsg, TWO_SECONDS);
}
