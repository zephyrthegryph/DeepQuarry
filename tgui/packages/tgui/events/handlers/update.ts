import { perf } from 'common/perf';
import { prepareWindowGeometry, setupDrag } from '../../drag';
import { prepareRequestedInterface } from '../../interfacePreparation';
import { logger } from '../../logging';
import { profileStartup, profileUpdate } from '../../profiling/hooks';
import { profileTransition } from '../../profiling/transitions';
import type { PayloadFieldSample } from '../../profiling/types';
import { resumeRenderer } from '../../renderer';
import { hasRevealed, revealWindow } from '../../reveal';
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

let resumeRequest = 0;

/** Invalidates an on-demand load when the server suspends or reuses the shell. */
export function cancelPendingResume(): void {
  resumeRequest++;
}

export function update(payload: UpdatePayload): void {
  const wasSuspended = Boolean(store.get(suspendedAtom));
  const interfaceName = payload.config?.interface?.name;
  const previousInterface = store.get(configAtom)?.interface?.name;
  const profiling = Boolean(
    payload.config?.client?.profiling ||
      store.get(configAtom)?.client?.profiling,
  );
  if (profiling && wasSuspended) {
    profileTransition(
      'backend-received',
      {
        previous_interface: previousInterface,
        next_interface: interfaceName,
        next_generation: payload.config?.window?.generation,
        native_shell: Boolean(payload.config?.window?.native_shell),
      },
      true,
    );
  }
  const profileStart = profiling ? (performance.now?.() ?? Date.now()) : 0;
  if (profiling && wasSuspended) {
    profileStartup('backend_received', interfaceName, {
      bytes: JSON.stringify(payload).length,
      prewarmed: Boolean(payload.config?.window?.prewarmed),
      nativeShell: Boolean(payload.config?.window?.native_shell),
      generation: payload.config?.window?.generation,
    });
  }
  if (profiling && payload.data?.dq_server_profile) {
    profileStartup('server_profile', interfaceName, {
      ...(payload.data.dq_server_profile as Record<string, unknown>),
      catalog_build_ms: payload.data.dq_catalog_build_ms,
    });
  }
  if (
    wasSuspended &&
    previousInterface &&
    interfaceName &&
    previousInterface !== interfaceName
  ) {
    store.set(gameDataAtom, {});
    store.set(gameStaticDataAtom, {});
  }
  // Install the complete new interface snapshot while the renderer still sees
  // the shell as suspended. Unsuspending first allows React to mount one frame
  // with the previous interface's/default geometry before this payload lands,
  // which appears as a wrong-sized/positioned cold-open flash.
  updateData(payload);
  if (wasSuspended) {
    const request = ++resumeRequest;
    const generation = payload.config?.window?.generation;
    // Start storage and route I/O together. Window.tsx will await the already
    // running geometry request once the route supplies its default dimensions.
    prepareWindowGeometry(payload.config?.window?.key);
    const preparation = prepareRequestedInterface(interfaceName);
    const finishResume = () => {
      const currentConfig = store.get(configAtom);
      if (
        request !== resumeRequest ||
        !store.get(suspendedAtom) ||
        currentConfig.interface?.name !== interfaceName ||
        currentConfig.window?.generation !== generation
      ) {
        return;
      }
      if (profiling) {
        profileStartup('interface_preparation_finished', interfaceName);
      }
      resume(payload);
      store.set(suspendedAtom, false);
      if (profiling) profileTransition('backend-applied-and-unsuspended');
    };
    if (preparation) {
      if (profiling) {
        profileStartup('interface_preparation_started', interfaceName);
      }
      preparation.then(finishResume, (error) => {
        logger.error(`failed to prepare interface ${interfaceName}`, error);
        finishResume();
      });
    } else {
      finishResume();
    }
  }
  if (profiling) {
    const profileFinish = performance.now?.() ?? Date.now();
    const payloadJson = JSON.stringify(payload);
    profileUpdate(
      payloadJson.length,
      profileFinish - profileStart,
      payloadFieldBreakdown(payload, payloadJson.length),
    );
    if (wasSuspended) {
      profileStartup('backend_applied', interfaceName, {
        duration: profileFinish - profileStart,
      });
    }
  }
}

function payloadFieldBreakdown(
  payload: UpdatePayload,
  totalBytes: number,
): PayloadFieldSample[] {
  const fields: PayloadFieldSample[] = [];
  const measure = (prefix: string, value: unknown, depth: number) => {
    try {
      fields.push({
        path: prefix,
        bytes: JSON.stringify(value).length,
        items: Array.isArray(value)
          ? value.length
          : value && typeof value === 'object'
            ? Object.keys(value).length
            : undefined,
      });
    } catch {
      // Backend payloads should be JSON-safe; omit a field if instrumentation
      // encounters something unusual instead of affecting the update.
    }
    if (
      totalBytes < 100_000 ||
      depth >= 2 ||
      !value ||
      typeof value !== 'object' ||
      Array.isArray(value)
    ) {
      return;
    }
    for (const [key, child] of Object.entries(value)) {
      measure(`${prefix}.${key}`, child, depth + 1);
    }
  };
  for (const [containerName, container] of [
    ['data', payload.data],
    ['static_data', payload.static_data],
    ['config', payload.config],
    ['shared', payload.shared],
  ] as const) {
    if (!container || typeof container !== 'object') continue;
    measure(containerName, container, 0);
  }
  return fields.sort((a, b) => b.bytes - a.bytes).slice(0, 12);
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
  const generation = payload.config?.window?.generation;
  // Failsafe reveal — RevealWindow (routes.tsx) is the primary, content-timed reveal.
  setTimeout(() => {
    perf.mark('resume/start');
    // Doublecheck if we are not re-suspended.
    if (store.get(suspendedAtom)) {
      return;
    }
    if (hasRevealed(generation)) {
      return;
    }

    revealWindow(generation);
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
