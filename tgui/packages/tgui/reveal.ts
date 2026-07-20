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

/** Reveal only the current acquisition of a non-suspended pooled shell. */
export function revealWindow(
  generation?: number,
  geometry?: ResolvedWindowGeometry,
): boolean {
  const config = store.get(configAtom);
  const currentGeneration = config?.window?.generation;
  if (
    store.get(suspendedAtom) ||
    (generation !== undefined && generation !== currentGeneration)
  ) {
    return false;
  }
  const nativePayload = buildNativeRevealPayload(geometry);
  profileStartup('window_revealed', config?.interface?.name, {
    generation: currentGeneration,
    atomicGeometry: Boolean(geometry?.size || geometry?.pos),
  });
  Byond.winset(Byond.windowId, nativePayload);
  Byond.sendMessage('visible', {
    generation: currentGeneration,
    geometry: nativePayload,
  });
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
