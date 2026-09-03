/**
 * @file
 * Window-reveal coordination.
 *
 * A pooled tgui window is cloned from a hidden native skin template
 * and must be revealed exactly once its content is ready — but for `<Window>`
 * interfaces "ready" means *after geometry has been applied*, otherwise the
 * window paints at BYOND's default size for a frame and then resizes (the
 * cold-open flicker).
 *
 * Two parties can reveal:
 *   - Window.tsx, which calls claimReveal() synchronously when it mounts and
 *     then revealWindow() only AFTER awaiting recallWindowGeometry().
 *   - The route-level fallback (<RevealWindow> in routes.tsx), which reveals any
 *     content that does NOT manage its own geometry (Pane-based UIs, error
 *     windows, and any interface not rooted in <Window>) the moment it mounts.
 *
 * React fires effects child-first, so a <Window> deep in the tree runs
 * claimReveal() before the parent <RevealWindow> runs revealIfUnclaimed() in the
 * same commit — the fallback correctly stands down for geometry-managed windows
 * and still covers everything else.
 *
 * The claim is module-global (one webpack runtime per BYOND window) and must be
 * reset when the window is suspended, because pooled windows are reused for
 * different interfaces: a Window-interface open claims, and if the next reuse is
 * a Pane-interface it must fall back to the route-level reveal again.
 */

import { getNativeWindowPosition, type ResolvedWindowGeometry } from './drag';
import { sendByondMessage } from './events/sendMessage';
import { configAtom, store, suspendedAtom } from './events/store';
import { profileStartup } from './profiling/hooks';
import {
  observedNativeGeometry,
  profileTransition,
} from './profiling/transitions';

let claimed = false;
let revealedGeneration: number | undefined;

type NativeRevealPayload = {
  'is-visible': true;
  pos?: string;
  size?: string;
};

type NativeGeometryPayload = Omit<NativeRevealPayload, 'is-visible'>;

/** Build one native transaction so BYOND cannot paint between resize and show. */
export function buildNativeRevealPayload(
  geometry?: ResolvedWindowGeometry,
): NativeRevealPayload {
  return {
    'is-visible': true,
    // DreamSeeker's native window geometry is integral. Sending a centered
    // half-pixel (common with odd dimensions and fractional display scaling)
    // is silently truncated by winset(), then our exact winget verification
    // waits its full timeout for a value the client can never report.
    ...(geometry?.pos && {
      pos: `${Math.round(geometry.pos[0])},${Math.round(geometry.pos[1])}`,
    }),
    ...(geometry?.size && {
      size: `${Math.round(geometry.size[0])}x${Math.round(geometry.size[1])}`,
    }),
  };
}

function buildNativeGeometryPayload(
  geometry?: ResolvedWindowGeometry,
): NativeGeometryPayload {
  const payload = buildNativeRevealPayload(geometry);
  const { 'is-visible': _visible, ...nativeGeometry } = payload;
  return nativeGeometry;
}

function isCurrentGeneration(generation?: number): boolean {
  return (
    !store.get(suspendedAtom) &&
    (generation === undefined ||
      generation === store.get(configAtom)?.window?.generation)
  );
}

function nativeGeometrySignature(observed: any): string | undefined {
  const size = observed?.size;
  const pos = observed?.pos;
  if (!size && !pos) return undefined;
  const sizeText = size ? `${size.x}x${size.y}` : '';
  const posText = pos ? `${pos.x},${pos.y}` : '';
  return `${sizeText}@${posText}`;
}

async function queryNativeGeometry(): Promise<any> {
  // BYOND returns the value itself for a single-property winget (for example,
  // `{x, y}` for size), not an object keyed by a semicolon-separated property
  // list. Query independently and normalize the result for matching/logging.
  const [size, pos] = await Promise.all([
    Byond.winget(Byond.windowId, 'size'),
    Byond.winget(Byond.windowId, 'pos'),
  ]);
  return { size, pos };
}

async function queryNativePresentation(): Promise<any> {
  const [geometry, alpha, visible] = await Promise.all([
    queryNativeGeometry(),
    Byond.winget(Byond.windowId, 'alpha'),
    Byond.winget(Byond.windowId, 'is-visible'),
  ]);
  return { ...geometry, alpha, 'is-visible': visible };
}

function geometryMatches(
  observed: any,
  expected: NativeGeometryPayload,
): boolean {
  const observedSize = observed?.size;
  const observedPos = observed?.pos;
  const expectedSize = expected.size?.match(/^(\d+)x(\d+)$/);
  const expectedPos = expected.pos?.match(/^(-?\d+),(-?\d+)$/);
  const closeEnough = (actual: number, target: number) =>
    Math.abs(actual - target) <= 1;
  return (
    (!expectedSize ||
      (observedSize &&
        closeEnough(observedSize.x, Number(expectedSize[1])) &&
        closeEnough(observedSize.y, Number(expectedSize[2])))) &&
    (!expectedPos ||
      (observedPos &&
        closeEnough(observedPos.x, Number(expectedPos[1])) &&
        closeEnough(observedPos.y, Number(expectedPos[2]))))
  );
}

async function waitForNativeGeometry(
  expected: NativeGeometryPayload,
): Promise<{ matched: boolean; observed?: string }> {
  const deadline = performance.now() + 500;
  let observed: any;
  try {
    do {
      observed = await queryNativeGeometry();
      if (geometryMatches(observed, expected)) {
        return { matched: true, observed: nativeGeometrySignature(observed) };
      }
      // Yield a frame before checking again. DreamSeeker can acknowledge the
      // winget call before the native OS window has committed its resize.
      // Hidden browser windows may throttle animation frames indefinitely.
      await new Promise<void>((resolve) => setTimeout(resolve, 16));
    } while (performance.now() < deadline);
  } catch {
    // Reveal still has a bounded fallback; telemetry records the mismatch.
  }
  return { matched: false, observed: nativeGeometrySignature(observed) };
}

function expectedViewportSize(size?: string): [number, number] | undefined {
  if (!size) return undefined;
  const match = /^(\d+)x(\d+)$/.exec(size);
  if (!match) return undefined;
  return [Number(match[1]), Number(match[2])];
}

function browserViewportSignature(): string {
  return `${window.innerWidth}x${window.innerHeight}`;
}

function browserPositionMatches(expectedPos?: string): boolean {
  if (!expectedPos) return true;
  const match = /^(-?\d+),(-?\d+)$/.exec(expectedPos);
  if (!match) return false;
  const actual = getNativeWindowPosition();
  const tolerance = Math.max(2, Math.ceil((window.devicePixelRatio || 1) * 2));
  return (
    Math.abs(actual[0] - Number(match[1])) <= tolerance &&
    Math.abs(actual[1] - Number(match[2])) <= tolerance
  );
}

async function waitForBrowserNativeGeometry(
  expected: NativeGeometryPayload,
): Promise<boolean> {
  const deadline = performance.now() + 32;
  do {
    if (
      browserViewportMatches(expected.size) &&
      browserPositionMatches(expected.pos)
    ) {
      return true;
    }
    await new Promise<void>((resolve) => setTimeout(resolve, 8));
  } while (performance.now() < deadline);
  return false;
}

/**
 * Native BYOND window dimensions are display pixels, while Chromium reports
 * its viewport in CSS pixels. At 125% display scaling a 400x500 native window
 * correctly has a 320x400 viewport; comparing the numbers directly imposed a
 * guaranteed 500 ms timeout on every open.
 */
export function browserViewportMatches(
  expectedSize?: string,
  viewportWidth = window.innerWidth,
  viewportHeight = window.innerHeight,
  pixelRatio = window.devicePixelRatio || 1,
): boolean {
  const expected = expectedViewportSize(expectedSize);
  if (!expected) return true;
  // Chromium reports integral CSS pixels while DreamSeeker reports integral
  // display pixels. At fractional DPI, rounding can compound in both directions
  // (422 CSS px at 125% may legitimately back a 526 px native viewport). Allow
  // two CSS pixels expressed in native units, while still rejecting a genuinely
  // stale pooled-window size by a wide margin.
  const tolerance = Math.max(2, Math.ceil(pixelRatio * 2));
  return (
    Math.abs(viewportWidth * pixelRatio - expected[0]) <= tolerance &&
    Math.abs(viewportHeight * pixelRatio - expected[1]) <= tolerance
  );
}

async function waitForBrowserViewport(
  expectedSize?: string,
): Promise<{ matched: boolean; observed: string }> {
  const expected = expectedViewportSize(expectedSize);
  if (!expected) {
    return { matched: true, observed: browserViewportSignature() };
  }
  const deadline = performance.now() + 500;
  do {
    // BYOND's native size maps to the browser viewport in this skin. Waiting
    // here prevents showing a correctly-sized OS window whose embedded browser
    // is still painting at the pooled shell's previous dimensions.
    if (browserViewportMatches(expectedSize)) {
      return { matched: true, observed: browserViewportSignature() };
    }
    await new Promise<void>((resolve) => setTimeout(resolve, 8));
  } while (performance.now() < deadline);
  return { matched: false, observed: browserViewportSignature() };
}

async function monitorRevealedGeometry(
  generation: number | undefined,
  expected: NativeGeometryPayload,
): Promise<void> {
  if (!store.get(configAtom)?.client?.profiling) return;
  const observations: string[] = [];
  let previousDelay = 0;
  for (const delay of [0, 50, 150, 400]) {
    if (delay > previousDelay) {
      await new Promise<void>((resolve) =>
        setTimeout(resolve, delay - previousDelay),
      );
    }
    previousDelay = delay;
    if (!isCurrentGeneration(generation)) return;
    try {
      const signature = nativeGeometrySignature(await queryNativeGeometry());
      if (signature) observations.push(signature);
    } catch {
      return;
    }
  }
  const unique = [...new Set(observations)];
  profileStartup('native_geometry_observed', undefined, {
    expectedSize: expected.size,
    expectedPos: expected.pos,
    first: observations[0],
    last: observations.at(-1),
    changes: Math.max(0, unique.length - 1),
  });
  if (unique.length > 1) {
    sendByondMessage('perf/flicker', {
      kind: 'post-reveal-geometry-change',
      generation,
      interface: store.get(configAtom)?.interface?.name,
      expected_size: expected.size,
      expected_pos: expected.pos,
      first: observations[0],
      last: observations.at(-1),
      changes: unique.length - 1,
    });
  }
}

/** Reveal only the current acquisition of a non-suspended pooled shell. */
export async function revealWindow(
  generation?: number,
  geometry?: ResolvedWindowGeometry,
): Promise<boolean> {
  const config = store.get(configAtom);
  const currentGeneration = config?.window?.generation;
  const nativeShell = Boolean(config?.window?.native_shell);
  if (!isCurrentGeneration(generation)) {
    return false;
  }
  const nativeGeometry = buildNativeGeometryPayload(geometry);
  const warmGeometry =
    Boolean(config?.window?.geometry_preapplied) &&
    browserViewportMatches(nativeGeometry.size) &&
    browserPositionMatches(nativeGeometry.pos);
  profileTransition('reveal-start', {
    requested_size: nativeGeometry.size,
    requested_pos: nativeGeometry.pos,
    native_shell: nativeShell,
  });
  if (nativeShell) {
    // Let DreamSeeker perform the native hidden->shown transition while the
    // OS window is fully transparent. Some clients center or paint a window
    // during winshow even when geometry was assigned while it was hidden.
    Byond.winset(Byond.windowId, { alpha: 0, 'is-visible': true });
    profileTransition('transparent-native-show-sent');
  }
  if ((nativeGeometry.size || nativeGeometry.pos) && !warmGeometry) {
    // Keep the shell hidden while DreamSeeker applies geometry. A single
    // winset containing is-visible can be painted in property order on cold
    // browser windows, exposing the template size for one frame. winget is a
    // client round trip and therefore confirms the preceding geometry command
    // has been processed before the separate show command is sent.
    Byond.winset(Byond.windowId, {
      ...nativeGeometry,
      ...(nativeShell ? { alpha: 0 } : { 'is-visible': false }),
    });
    const browserObservedGeometry =
      await waitForBrowserNativeGeometry(nativeGeometry);
    const verification = browserObservedGeometry
      ? { matched: true, observed: 'browser-observed' }
      : await waitForNativeGeometry(nativeGeometry);
    profileTransition('native-geometry-verified', {
      matched: verification.matched,
      observed: verification.observed,
      source: browserObservedGeometry ? 'browser' : 'winget',
      requested_size: nativeGeometry.size,
      requested_pos: nativeGeometry.pos,
    });
    if (!verification.matched && config?.client?.profiling) {
      sendByondMessage('perf/flicker', {
        kind: 'pre-reveal-geometry-mismatch',
        generation: currentGeneration,
        interface: config?.interface?.name,
        expected_size: nativeGeometry.size,
        expected_pos: nativeGeometry.pos,
        observed: verification.observed,
      });
    }
    const viewport = await waitForBrowserViewport(nativeGeometry.size);
    profileTransition('browser-viewport-verified', {
      matched: viewport.matched,
      observed: viewport.observed,
      requested_size: nativeGeometry.size,
    });
    if (!viewport.matched && config?.client?.profiling) {
      sendByondMessage('perf/flicker', {
        kind: 'pre-reveal-viewport-mismatch',
        generation: currentGeneration,
        interface: config?.interface?.name,
        expected_size: nativeGeometry.size,
        observed: viewport.observed,
      });
    }
    if (!isCurrentGeneration(generation)) {
      return false;
    }
  }
  profileStartup('window_revealed', config?.interface?.name, {
    generation: currentGeneration,
    verifiedGeometry: Boolean(nativeGeometry.size || nativeGeometry.pos),
    warmGeometry,
  });
  profileTransition('opacity-reveal-sending', {
    requested_size: nativeGeometry.size,
    requested_pos: nativeGeometry.pos,
  });
  Byond.winset(
    Byond.windowId,
    nativeShell ? { alpha: 255 } : { 'is-visible': true },
  );
  revealedGeneration = currentGeneration;
  profileTransition('opacity-reveal-sent');
  void samplePresentedTransition(currentGeneration);
  Byond.sendMessage('visible', {
    generation: currentGeneration,
    geometry: nativeGeometry,
  });
  void monitorRevealedGeometry(currentGeneration, nativeGeometry);
  return true;
}

async function samplePresentedTransition(generation?: number): Promise<void> {
  let elapsed = 0;
  for (const delay of [0, 16, 50, 150]) {
    if (delay > elapsed) {
      await new Promise<void>((resolve) =>
        setTimeout(resolve, delay - elapsed),
      );
    }
    elapsed = delay;
    if (!isCurrentGeneration(generation)) return;
    try {
      const observed = await queryNativePresentation();
      profileTransition(
        `post-opacity-${delay}ms`,
        observedNativeGeometry(observed),
      );
    } catch {
      profileTransition(`post-opacity-${delay}ms`, {
        native_query_failed: true,
      });
    }
  }
  requestAnimationFrame(() => {
    profileTransition('first-animation-frame');
    requestAnimationFrame(() => profileTransition('second-animation-frame'));
  });
}

/**
 * A layout (Window) takes ownership of revealing — it will call revealWindow()
 * itself after applying geometry, so the route-level fallback must not pre-empt
 * it and flash the window at default size.
 */
export function claimReveal(): void {
  claimed = true;
}

export function hasRevealed(generation?: number): boolean {
  return generation !== undefined && revealedGeneration === generation;
}

/** Route-level fallback reveal: fires only if no layout claimed the reveal. */
export function revealIfUnclaimed(generation?: number): void {
  if (!claimed) {
    revealWindow(generation);
  }
}

/** Reset the claim on suspend so a reused pooled window reveals again next open. */
export function resetReveal(): void {
  claimed = false;
  revealedGeneration = undefined;
}
