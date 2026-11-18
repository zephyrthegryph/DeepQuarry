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

/** The shortest a fitted window is made (CSS px): a title bar and a line or two. */
export const FIT_MIN_HEIGHT = 120;
/** A fit smaller than this (CSS px) is not worth a resize: layout noise, a blinking line. */
export const FIT_STEP = 8;

/**
 * How far (CSS px, either sign) the window's inner height should change to fit content that wants `want`: clamped to
 * [min, max], and 0 when the change is under FIT_STEP.
 */
export function fitTarget(
  want: number,
  inner: number,
  limits: { min?: number; max: number },
): number {
  const target = Math.min(
    limits.max,
    Math.max(limits.min ?? FIT_MIN_HEIGHT, Math.ceil(want)),
  );
  const delta = target - inner;
  return Math.abs(delta) < FIT_STEP ? 0 : delta;
}

/**
 * Auto-fit for every window (doc/tgui_preview.md "Window fit"): the inner height (CSS px, the viewport the window must
 * have; for a docked window, the height below `originTop`, its column entry's top) at which the window's content shows whole with no space left under it, or null when the window cannot be
 * measured (a map or browser control has no size of its own, or there is no window content).
 *
 * Unlike measureNaturalBottom (a prompt that only grows), every scroll box and fill layout is released to its content:
 * a fill Section, a scrollable list and the window's own scroller take the height of what is in them, so the result is
 * the height the whole content wants. The caller clamps it to the screen and to the window's limits; a list longer than
 * that scrolls as before. Everything is restored before returning, in the same task, so nothing paints.
 */
export function measureFitHeight(
  scope: Document | Element = document,
  originTop = 0,
): number | null {
  const content = scope.querySelector<HTMLElement>('.Window__content');
  if (!content) return null;
  // A window that keeps its size (autoFit={false}: a camera or map view).
  if (content.closest('[data-autofit="off"]')) return null;
  // A map or embedded browser control fills whatever space it is given: there is no content height to fit to.
  if (content.querySelector('.ByondUi, .NanoMap, [class*="Map__"]'))
    return null;
  const root =
    content.querySelector<HTMLElement>(':scope > .Window__contentPadding') ??
    content;
  const saved: [HTMLElement, string][] = [];
  const release = (el: HTMLElement, css: string) => {
    saved.push([el, el.style.cssText]);
    el.style.cssText += css;
  };
  const scrollTop = content.scrollTop;
  release(root, ';height:auto !important;min-height:0 !important');
  for (const el of root.querySelectorAll<HTMLElement>('*')) {
    const style = getComputedStyle(el);
    const scroller = style.overflowY === 'auto' || style.overflowY === 'scroll';
    // Percentage and flex heights resolve against a parent that is no longer fixed; a scroll box shows all it holds.
    if (scroller) {
      release(
        el,
        ';overflow-y:visible !important;max-height:none !important;height:auto !important;flex-basis:auto !important' +
          // A fill section's scroll box is stretched absolutely over its section (top: 0; bottom: 0): in flow it takes its content's height.
          (style.position === 'absolute'
            ? ';position:relative !important;inset:auto !important'
            : ''),
      );
    } else if (style.height.endsWith('%') || el.style.height.endsWith('%')) {
      release(el, ';height:auto !important');
    }
  }
  try {
    content.scrollTop = 0;
    const box = root.getBoundingClientRect();
    const cs = getComputedStyle(root);
    const pad = Number.parseFloat(getComputedStyle(content).paddingBottom) || 0;
    const margin = Number.parseFloat(cs.marginBottom) || 0;
    return Math.ceil(box.top + box.height + margin + pad - originTop);
  } finally {
    for (let i = saved.length - 1; i >= 0; i--) {
      saved[i][0].style.cssText = saved[i][1];
    }
    content.scrollTop = scrollTop;
  }
}
