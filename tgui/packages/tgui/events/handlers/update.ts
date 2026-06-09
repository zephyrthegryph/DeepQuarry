import { perf } from 'common/perf';
import { setupDrag } from '../../drag';
import { logger } from '../../logging';
import { resumeRenderer } from '../../renderer';
import { revealWindow } from '../../reveal';
import {
  configAtom,
  gameDataAtom,
  gameStaticDataAtom,
  sharedAtom,
  store,
  suspendedAtom,
} from '../store';
import type { BackendState } from '../types';

/// --------- Handlers ------------------------------------------------------///

type UpdatePayload = Omit<BackendState<Record<string, unknown>>, 'act'> & {
  static_data: Record<string, unknown>;
};

export function update(payload: UpdatePayload): void {
  if (store.get(suspendedAtom)) {
    resume(payload);
    store.set(suspendedAtom, false);
  }
  updateData(payload);
}

/// --------- Helpers -------------------------------------------------------///

/**
 * Failsafe delay (ms) before resume() reveals the window. The PRIMARY reveal is
 * done by <RevealWindow> in routes.tsx the moment the real interface content mounts
 * (after its lazy chunk loads and Window.tsx has set geometry) — that's what makes a
 * window appear already-sized instead of flashing at default geometry then resizing.
 * This resume() reveal is kept only as a safety net: if RevealWindow somehow never
 * fires for a window (an unwrapped routing path), the window still becomes visible
 * after this delay rather than being stranded hidden.
 *
 * It MUST be longer than a worst-case COLD interface load (first use of a chunk in a
 * given window's runtime: fetch + script execute + mount), or the failsafe wins the
 * race and reveals the window empty-at-default-geometry before the content mounts —
 * which is exactly the cold-open flicker. A warm open mounts in a few ms; a cold open
 * is well under a couple seconds, so this is set generously. The only cost of a large
 * value is that a genuinely-broken interface (RevealWindow never fires) takes this
 * long to appear — an acceptable trade for never flickering and never stranding hidden.
 */
const RESUME_REVEAL_FAILSAFE_MS = 2500;

/** Resumes the tgui window if suspended */
function resume(payload: UpdatePayload): void {
  // Show the payload
  logger.log('Resuming:', payload);
  // Signal renderer that we have resumed
  resumeRenderer();
  // Setup drag
  setupDrag();
  // Failsafe reveal — RevealWindow (routes.tsx) is the primary, content-timed reveal.
  setTimeout(() => {
    perf.mark('resume/start');
    // Doublecheck if we are not re-suspended.
    if (store.get(suspendedAtom)) {
      return;
    }

    revealWindow();
    perf.mark('resume/finish');

    if (process.env.NODE_ENV !== 'production') {
      logger.log('visible in', perf.measure('render/finish', 'resume/finish'));
    }
  }, RESUME_REVEAL_FAILSAFE_MS);
}

/** Delegates update data to the appropriate store */
function updateData(payload: UpdatePayload): void {
  if (payload.config) {
    store.set(configAtom, (prev) => ({
      ...prev,
      ...payload.config,
    }));
  }

  if (payload.static_data) {
    store.set(gameStaticDataAtom, (prev) => ({
      ...prev,
      ...payload.static_data,
    }));
  }

  if (payload.data) {
    store.set(gameDataAtom, (prev) => ({
      ...prev,
      ...payload.data,
    }));
  }

  if (payload.shared) {
    const newShared = {} as Record<string, unknown>;

    for (const key in payload.shared) {
      const value = payload.shared[key];
      if (value === '') {
        newShared[key] = undefined;
      } else {
        newShared[key] = JSON.parse(value);
      }
    }

    store.set(sharedAtom, (prev) => ({
      ...prev,
      ...newShared,
    }));
  }
}
