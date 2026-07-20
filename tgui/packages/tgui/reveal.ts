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

import type { ResolvedWindowGeometry } from './drag';
import { configAtom, store, suspendedAtom } from './events/store';
import { profileStartup } from './profiling/hooks';

let claimed = false;

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
    ...(geometry?.pos && { pos: `${geometry.pos[0]},${geometry.pos[1]}` }),
    ...(geometry?.size && { size: `${geometry.size[0]}x${geometry.size[1]}` }),
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

function geometryMatches(
  observed: any,
  expected: NativeGeometryPayload,
): boolean {
  const observedSize = observed?.size;
  const observedPos = observed?.pos;
  const actualSize = observedSize ? `${observedSize.x}x${observedSize.y}` : '';
  const actualPos = observedPos ? `${observedPos.x},${observedPos.y}` : '';
  return (
    (!expected.size || expected.size === actualSize) &&
    (!expected.pos || expected.pos === actualPos)
  );
}

async function waitForNativeGeometry(
  expected: NativeGeometryPayload,
): Promise<{ matched: boolean; observed?: string }> {
  const deadline = performance.now() + 500;
  let observed: any;
  try {
    do {
      observed = await Byond.winget(Byond.windowId, 'size;pos');
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
    if (
      window.innerWidth === expected[0] &&
      window.innerHeight === expected[1]
    ) {
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
      const signature = nativeGeometrySignature(
        await Byond.winget(Byond.windowId, 'size;pos'),
      );
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
    Byond.sendMessage('perf/flicker', {
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
  if (nativeShell) {
    // Let DreamSeeker perform the native hidden->shown transition while the
    // OS window is fully transparent. Some clients center or paint a window
    // during winshow even when geometry was assigned while it was hidden.
    Byond.winset(Byond.windowId, { alpha: 0, 'is-visible': true });
  }
  if (nativeGeometry.size || nativeGeometry.pos) {
    // Keep the shell hidden while DreamSeeker applies geometry. A single
    // winset containing is-visible can be painted in property order on cold
    // browser windows, exposing the template size for one frame. winget is a
    // client round trip and therefore confirms the preceding geometry command
    // has been processed before the separate show command is sent.
    Byond.winset(Byond.windowId, {
      ...nativeGeometry,
      ...(nativeShell ? { alpha: 0 } : { 'is-visible': false }),
    });
    const verification = await waitForNativeGeometry(nativeGeometry);
    if (!verification.matched && config?.client?.profiling) {
      Byond.sendMessage('perf/flicker', {
        kind: 'pre-reveal-geometry-mismatch',
        generation: currentGeneration,
        interface: config?.interface?.name,
        expected_size: nativeGeometry.size,
        expected_pos: nativeGeometry.pos,
        observed: verification.observed,
      });
    }
    const viewport = await waitForBrowserViewport(nativeGeometry.size);
    if (!viewport.matched && config?.client?.profiling) {
      Byond.sendMessage('perf/flicker', {
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
  });
  Byond.winset(
    Byond.windowId,
    nativeShell ? { alpha: 255 } : { 'is-visible': true },
  );
  Byond.sendMessage('visible', {
    generation: currentGeneration,
    geometry: nativeGeometry,
  });
  void monitorRevealedGeometry(currentGeneration, nativeGeometry);
  return true;
}

/**
 * A layout (Window) takes ownership of revealing — it will call revealWindow()
 * itself after applying geometry, so the route-level fallback must not pre-empt
 * it and flash the window at default size.
 */
export function claimReveal(): void {
  claimed = true;
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
}
