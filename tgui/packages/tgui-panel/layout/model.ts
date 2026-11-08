/**
 * The right-hand column's place on the screen, as pure maths: the main
 * window's client area from what BYOND reports, the column in it, the
 * map/column split from a pointer, and the page browser's fit to its pane
 * (doc/rewrite/proposals/window_system.md section 12). geometry.ts measures;
 * this file only decides.
 */

export type Point = { x: number; y: number };

export type Rect = { x: number; y: number; w: number; h: number };

/** The percent of the main split the map takes when the splitter is dragged to screen x. */
export function mapSplitFromX(
  client: Rect,
  splitWidth: number,
  x: number,
): number {
  const width = splitWidth > 0 ? Math.min(splitWidth, client.w) : client.w;
  if (!(width > 0)) {
    return MAP_SPLIT_MIN;
  }
  return Math.min(
    MAP_SPLIT_MAX,
    Math.max(MAP_SPLIT_MIN, Math.round(((x - client.x) / width) * 100)),
  );
}

/** The main window's split between the map and the right-hand column is kept in this range (percent the map takes). */
export const MAP_SPLIT_MIN = 10;

export const MAP_SPLIT_MAX = 90;

/** What BYOND reports for the main window (winget), parsed. */
export type MainReport = {
  pos: Point | null;
  outerSize: Point | null;
  size: Point | null;
  innerSize: Point | null;
  maximized: boolean;
};

/**
 * The main window's outer rect and client area in screen pixels, plus the part
 * of the client area that is on the screen (`visible`: what the float window is
 * held inside; BYOND's inner-size leaves out the title bar, menu and borders). `screen` is the monitor's work area in screen
 * pixels.
 *
 * A maximized window reports the pos and size it has when NOT maximized (the
 * skin's 640x440 centred on the screen), only outer-size and inner-size are
 * live. Taking that pos as the origin put the "main window" at the middle of
 * the screen, so the float window could not go above or left of it. A
 * maximized window is as large as its outer size and centred on the work
 * area (its borders hang over the edges evenly), so its origin follows from
 * those.
 */
export function mainRects(
  report: MainReport,
  screen: Rect | null,
): { outer: Rect; client: Rect; visible: Rect } | null {
  const outerSize = report.outerSize ?? report.size;
  if (!outerSize || outerSize.x <= 0 || outerSize.y <= 0) {
    return null;
  }
  let origin: Point;
  if (report.maximized) {
    const work = screen ?? { x: 0, y: 0, w: outerSize.x, h: outerSize.y };
    origin = {
      x: Math.round(work.x + (work.w - outerSize.x) / 2),
      y: Math.round(work.y + (work.h - outerSize.y) / 2),
    };
  } else if (report.pos) {
    origin = report.pos;
  } else {
    return null;
  }
  const outer = { x: origin.x, y: origin.y, w: outerSize.x, h: outerSize.y };
  const clientSize =
    report.innerSize ??
    (report.maximized
      ? { x: screen?.w ?? outerSize.x, y: screen?.h ?? outerSize.y }
      : (report.size ?? outerSize));
  const client = clientRect(outer, clientSize);
  // Contained and snapped to the client area only: the title bar, menu and borders are not inside the game window.
  const visible = screen ? intersect(client, screen) : client;
  return { outer, client, visible };
}

/** The overlap of two rects (zero-sized when they do not meet). */
export function intersect(a: Rect, b: Rect): Rect {
  const x = Math.max(a.x, b.x);
  const y = Math.max(a.y, b.y);
  return {
    x,
    y,
    w: Math.max(0, Math.min(a.x + a.w, b.x + b.w) - x),
    h: Math.max(0, Math.min(a.y + a.h, b.y + b.h) - y),
  };
}

/**
 * The main window's client area in screen pixels from its outer rect and the
 * client size (borders are even on the sides and the bottom; the title bar and top border are what is left above).
 */
export function clientRect(outer: Rect, client: Point): Rect {
  const border = Math.max(0, (outer.w - client.x) / 2);
  const top = Math.max(0, outer.h - client.y - border);
  return {
    x: outer.x + border,
    y: outer.y + top,
    w: Math.min(client.x, outer.w),
    h: Math.min(client.y, outer.h),
  };
}

/** The right-hand column in screen pixels: as wide and tall as measured, against the right edge of the client area. */
export function columnRect(client: Rect, column: Point): Rect {
  const w = Math.min(Math.max(column.x, 0), client.w);
  const h = Math.min(Math.max(column.y, 0), client.h);
  return { x: client.x + client.w - w, y: client.y, w, h };
}

/** How far (screen pixels) a docked chat is dragged before it pops out into a window. */
export const POP_OUT_DISTANCE = 14;

/**
 * The size to give the chat browser so it fits its pane. `reported` is what the
 * pane window says it is (which can be stale: a hidden pane keeps the size it
 * had), `expected` is what the host (the column's chat part, or the float
 * window) really has. Never bigger than the host, or the page overflows the
 * screen; with no expectation the report is used.
 */
export function fitBrowserSize(reported: Point, expected: Point | null): Point {
  if (!expected || !(expected.x > 0) || !(expected.y > 0)) {
    return reported;
  }
  return {
    x: Math.min(reported.x, expected.x),
    y: Math.min(reported.y, expected.y),
  };
}
