/**
 * Content-fit sizing for small modal windows (alerts, text/list/number/key prompts).
 *
 * A prompt's height can't be guessed from the message length: wrapping depends on
 * the font, the window width and the DPI scale. Instead the window measures how far
 * its content actually reaches and grows to show all of it. It only ever grows, so
 * the requested size stays a lower bound and a measurement can never oscillate.
 */

/** Sub-pixel layout noise below this never triggers a resize. */
export const FIT_TOLERANCE = 1;

/**
 * Most a window may grow by fitting (CSS px) over the requested size. Content whose own
 * height follows the window (a stretched item whose margin overflows its parent, a
 * fill list) makes every grow demand another one; the cap ends that runaway.
 */
export const FIT_MAX_GROWTH = 240;

/** The part of `over` that may still be granted after `grown` px of earlier growth. */
export function fitGrowth(over: number, grown: number): number {
  return Math.max(0, Math.min(over, FIT_MAX_GROWTH - grown));
}

/** How far (CSS px) past the current window bottom the content reaches; 0 when it fits. */
export function fitOverflow(
  contentBottom: number,
  windowInnerHeight: number,
): number {
  const over = contentBottom - windowInnerHeight;
  return over > FIT_TOLERANCE ? Math.ceil(over) : 0;
}

/**
 * Lowest point the content reaches inside `root`, in viewport CSS px. Each element's
 * bottom is extended by the bottom padding and border of its ancestors up to and
 * including `root`, because that space sits below the element in the window.
 */
export function measureContentBottom(root: HTMLElement): number {
  const trail = new Map<Element, number>();
  const tail = (el: Element): number => {
    const known = trail.get(el);
    if (known !== undefined) {
      return known;
    }
    const style = getComputedStyle(el);
    const own =
      (Number.parseFloat(style.paddingBottom) || 0) +
      (Number.parseFloat(style.borderBottomWidth) || 0);
    const parent = el === root ? null : el.parentElement;
    const total = own + (parent ? tail(parent) : 0);
    trail.set(el, total);
    return total;
  };

  let bottom = root.getBoundingClientRect().bottom;
  for (const el of root.querySelectorAll('*')) {
    const rect = el.getBoundingClientRect();
    if (rect.height === 0 && rect.width === 0) {
      continue;
    }
    const parent = el.parentElement;
    const below = parent ? tail(parent) : 0;
    bottom = Math.max(bottom, rect.bottom + below);
  }
  return Math.max(bottom, root.scrollHeight + root.getBoundingClientRect().top);
}
