/**
 * Content-fit sizing for small modal windows (alerts, text/list/number/key prompts).
 *
 * A prompt's height can't be guessed from the message length: wrapping depends on
 * the font, the window width and the DPI scale. Instead the window measures the
 * content's natural height and grows to show all of it. The measurement is taken
 * with the content's height released from the window (see measureNaturalBottom), so
 * the window's own size cannot change it and growing cannot feed back into it. The
 * window only ever grows, so the requested size stays a lower bound.
 */

/** Sub-pixel layout noise below this never triggers a resize. */
export const FIT_TOLERANCE = 1;

/** How far (CSS px) past the current window bottom the content reaches; 0 when it fits. */
export function fitOverflow(
  contentBottom: number,
  windowInnerHeight: number,
): number {
  const over = contentBottom - windowInnerHeight;
  return over > FIT_TOLERANCE ? Math.ceil(over) : 0;
}

/**
 * Lowest point (viewport CSS px) the window needs for `root` at its natural height,
 * including root's bottom margin.
 *
 * `root` normally has a definite height tied to the window (calc(100% - 1rem)), which
 * makes fill/stretched children follow the window. While measuring, its height is
 * released to auto so percentage heights and flex growth resolve to content size, and
 * scroll containers (long lists) are collapsed so they never ask the window to grow.
 * Everything is restored before returning, within the same synchronous task, so
 * nothing paints and no resize is observed.
 */
export function measureNaturalBottom(root: HTMLElement): number {
  const savedHeight = root.style.height;
  const collapsed: [HTMLElement, string][] = [];
  root.style.height = 'auto';
  for (const el of root.querySelectorAll<HTMLElement>('*')) {
    const style = getComputedStyle(el);
    if (style.overflowY === 'auto' || style.overflowY === 'scroll') {
      collapsed.push([el, el.style.maxHeight]);
      el.style.maxHeight = '0px';
    }
  }
  try {
    const margin = Number.parseFloat(getComputedStyle(root).marginBottom) || 0;
    return root.getBoundingClientRect().bottom + margin;
  } finally {
    root.style.height = savedHeight;
    for (const [el, maxHeight] of collapsed) {
      el.style.maxHeight = maxHeight;
    }
  }
}
