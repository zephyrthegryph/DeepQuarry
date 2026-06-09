/**
 * @file
 * Window-reveal coordination.
 *
 * A tgui window is born hidden (`is-visible=0`, set DM-side for pooled windows)
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

let claimed = false;

/** Reveal the window now and notify DM. Idempotent (winset is harmless to repeat). */
export function revealWindow(): void {
  Byond.winset(Byond.windowId, { 'is-visible': true });
  Byond.sendMessage('visible');
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
export function revealIfUnclaimed(): void {
  if (!claimed) {
    revealWindow();
  }
}

/** Reset the claim on suspend so a reused pooled window reveals again next open. */
export function resetReveal(): void {
  claimed = false;
}
