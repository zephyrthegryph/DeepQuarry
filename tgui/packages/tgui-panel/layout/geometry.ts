/**
 * The right-hand column's place on the screen, measured from the main window
 * (the column page's drop checks, column/host.ts), the live map/column split
 * the page's left edge drags, and fitting the page's browser to its pane
 * (doc/rewrite/proposals/window_system.md section 12). Pure maths in model.ts.
 */
import {
  columnRect,
  fitBrowserSize,
  MAP_SPLIT_MAX,
  MAP_SPLIT_MIN,
  type MainReport,
  mainRects,
  mapSplitFromX,
  type Point,
  type Rect,
} from './model';

/** The right-hand split, the column page's pane and browser (SKIN_RPANE_SPLIT, output_browser, SKIN_CHAT_BROWSER). */
const COLUMN_SPLIT = 'rpane.rpanewindow';
const OUTPUT_PANE = 'output_browser';
const CHAT_BROWSER = 'browseroutput';
/** The main window's split between the map and the right-hand column (SKIN_MAIN_SPLIT). */
const MAIN_SPLIT = 'mainwindow.mainvsplit';

const pixelRatio = () => window.devicePixelRatio || 1;

const isPoint = (value: unknown): value is Point =>
  !!value &&
  typeof (value as Point).x === 'number' &&
  typeof (value as Point).y === 'number';

type Bounds = { outer: Rect; client: Rect; visible: Rect };

const asPoint = (value: unknown): Point | null =>
  isPoint(value) ? value : null;

/** The monitor work area the chat is on, in screen pixels (like the other window geometry). */
function screenArea(): Rect | null {
  const screen = window.screen as Screen & {
    availLeft?: number;
    availTop?: number;
  };
  const ratio = pixelRatio();
  const w = screen.availWidth * ratio;
  const h = screen.availHeight * ratio;
  if (!(w > 0) || !(h > 0)) {
    return null;
  }
  return {
    x: Math.round((screen.availLeft ?? 0) * ratio),
    y: Math.round((screen.availTop ?? 0) * ratio),
    w: Math.round(w),
    h: Math.round(h),
  };
}

/**
 * The main window's outer rect, client area and visible part in screen pixels:
 * what the float window is kept inside, and where the right-hand column is.
 */
export async function mainBounds(): Promise<Bounds | null> {
  try {
    const got = await Byond.winget('mainwindow', [
      'pos',
      'outer-size',
      'size',
      'inner-size',
      'is-maximized',
    ]);
    const report: MainReport = {
      pos: asPoint(got?.pos),
      outerSize: asPoint(got?.['outer-size']),
      size: asPoint(got?.size),
      innerSize: asPoint(got?.['inner-size']),
      maximized:
        got?.['is-maximized'] === true || got?.['is-maximized'] === 'true',
    };
    const screen = screenArea();
    const bounds = mainRects(report, screen);
    console.log('chat layout: main window', {
      got,
      report,
      screen,
      ratio: pixelRatio(),
      ...bounds,
    });
    return bounds;
  } catch {
    return null;
  }
}

/** The right-hand column (stat panel and chat) in screen pixels, or null when it cannot be told. */
export async function measureColumn(main: Bounds | null): Promise<Rect | null> {
  if (!main) {
    return null;
  }
  try {
    const column = await Byond.winget(COLUMN_SPLIT, 'size');
    return isPoint(column) ? columnRect(main.client, column) : null;
  } catch {
    return null;
  }
}

/** The main window's map/column split (percent the map takes), or null when it cannot be told or is out of range. */
export async function measureMapSplit(): Promise<number | null> {
  try {
    const got = await Byond.winget('mainwindow.mainvsplit', 'splitter');
    const split = Math.round(Number(got));
    return Number.isFinite(split) &&
      split >= MAP_SPLIT_MIN &&
      split <= MAP_SPLIT_MAX
      ? split
      : null;
  } catch {
    return null;
  }
}

/** Splitter updates go out at most this often while dragging (about 30 per second). */
export const SPLIT_INTERVAL_MS = 33;

/**
 * Drags the split between the map and the column live from the column
 * page's left edge. BYOND's own splitter only applies on release, so the page
 * draws the handle and sets the splitter itself, at most every
 * SPLIT_INTERVAL_MS, then reports the final value (onDone) so the server
 * remembers it.
 */
export function startMapSplitDrag(
  event: React.PointerEvent<HTMLElement>,
  onDone: (value: number) => void,
): void {
  if (event.button !== 0) {
    return;
  }
  event.stopPropagation();
  const target = event.currentTarget;
  const pointer = event.pointerId;
  target.setPointerCapture(pointer);
  const ratio = pixelRatio();
  let latest: Point = { x: event.screenX, y: event.screenY };
  let ctx: { main: Bounds | null; width: number } | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let lastAt = 0;
  let lastValue: number | null = null;

  const valueNow = (): number | null =>
    ctx?.main
      ? mapSplitFromX(ctx.main.client, ctx.width, latest.x * ratio)
      : null;

  const push = (): number | null => {
    timer = undefined;
    const value = valueNow();
    if (value === null || value === lastValue) {
      return value;
    }
    lastValue = value;
    lastAt = performance.now();
    Byond.winset(MAIN_SPLIT, 'splitter', `${value}`);
    return value;
  };

  const schedule = () => {
    if (timer !== undefined || !ctx) {
      return;
    }
    const wait = Math.max(0, SPLIT_INTERVAL_MS - (performance.now() - lastAt));
    timer = setTimeout(push, wait);
  };

  const move = (e: PointerEvent) => {
    latest = { x: e.screenX, y: e.screenY };
    schedule();
  };

  const end = () => {
    target.removeEventListener('pointermove', move);
    target.removeEventListener('pointerup', end);
    target.removeEventListener('pointercancel', end);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
    clearTimeout(timer);
    const value = push() ?? lastValue;
    console.log('column: map split drag ended', { value });
    if (value !== null) {
      onDone(value);
    }
  };

  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  mainBounds().then(async (main) => {
    let width = 0;
    try {
      const got = await Byond.winget(MAIN_SPLIT, 'size');
      width = isPoint(got) ? got.x : 0;
    } catch {
      width = 0;
    }
    ctx = { main, width };
    schedule();
  });
}

/**
 * Sizes the column page's browser to its pane once the layout settles (on
 * start, a moment after, and when the server says the pane is seated). The
 * anchors keep it right through every later resize. The pane window's own
 * size can be stale (a pane that was hidden keeps the size it had), so the
 * size is held to what the column split reports.
 */
export async function fitChatBrowser(reason: string): Promise<void> {
  try {
    const pane = await Byond.winget(OUTPUT_PANE, 'size');
    if (!isPoint(pane)) {
      console.log('column: fit skipped, pane size unknown', { reason, pane });
      return;
    }
    const column = await Byond.winget(COLUMN_SPLIT, 'size');
    const size = fitBrowserSize(pane, isPoint(column) ? column : null);
    console.log('column: fit the page browser', { reason, pane, column, size });
    Byond.winset(CHAT_BROWSER, { pos: '0,0', size: `${size.x}x${size.y}` });
  } catch (error) {
    console.log('column: fit the page browser failed', { reason, error });
  }
}
