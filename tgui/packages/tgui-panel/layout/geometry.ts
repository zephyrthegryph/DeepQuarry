import {
  type ChatMode,
  columnRect,
  dockShare,
  dockTarget,
  dragPosition,
  fitRect,
  fitSize,
  MAP_SPLIT_MAX,
  MAP_SPLIT_MIN,
  type MainReport,
  mainRects,
  type Point,
  poppedOut,
  type Rect,
  resizeSize,
  SHARE_DEFAULT,
  SNAP_DISTANCE,
  shareFromHeights,
  snapRect,
} from './model';

/** The skin's float window and the right-hand split (SKIN_CHAT_FLOAT_WINDOW, SKIN_RPANE_SPLIT). */
const FLOAT_WINDOW = 'chat_float';
const COLUMN_SPLIT = 'rpane.rpanewindow';

const pixelRatio = () => window.devicePixelRatio || 1;

const isPoint = (value: unknown): value is Point =>
  !!value &&
  typeof (value as Point).x === 'number' &&
  typeof (value as Point).y === 'number';

async function floatGeometry(): Promise<{ pos: Point; size: Point } | null> {
  try {
    const got = await Byond.winget(FLOAT_WINDOW, ['pos', 'size']);
    return isPoint(got?.pos) && isPoint(got?.size)
      ? { pos: got.pos, size: got.size }
      : null;
  } catch {
    return null;
  }
}

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
async function measureColumn(main: Bounds | null): Promise<Rect | null> {
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

/** The chat's share of the right-hand column right now, or null when it cannot be told. */
export async function measureShare(): Promise<number | null> {
  try {
    const column = await Byond.winget(COLUMN_SPLIT, 'size');
    if (!isPoint(column)) {
      return null;
    }
    return shareFromHeights(window.innerHeight * pixelRatio(), column.y);
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

type DragHandlers = {
  /** The pin a drop would make right now, while dragging (null when none). */
  onHint?: (hint: 'top' | 'bottom' | null, share?: number) => void;
  /** The drop landed over the right-hand column: dock there. */
  onPin: (mode: ChatMode, share: number) => void;
};

/**
 * Drags the float window with the mouse, with no OS title bar: the pointer is
 * captured by the strip and the window position follows the mouse deltas in
 * physical pixels (winset pos). Dropping with the pointer over the main
 * window's right-hand column docks the chat there, the upper half to the top
 * and the lower half to the bottom; the hint shows that target while dragging.
 */
export function startWindowDrag(
  event: React.PointerEvent<HTMLElement>,
  handlers: DragHandlers,
): void {
  if (event.button !== 0) {
    return;
  }
  const target = event.currentTarget;
  const pointer = event.pointerId;
  target.setPointerCapture(pointer);
  const startMouse: Point = { x: event.screenX, y: event.screenY };
  const ratio = pixelRatio();
  let start: { pos: Point; size: Point } | null = null;
  let area: Rect | null = null;
  let column: Rect | null = null;
  let latest: Point = startMouse;
  let frame = 0;
  let last: Point | null = null;
  let hint: 'top' | 'bottom' | null = null;
  let hintShare = 0;

  const placedRect = (): Rect | null => {
    if (!start) {
      return null;
    }
    const pos = dragPosition(start.pos, startMouse, latest, ratio);
    const fitted = fitRect(
      { x: pos.x, y: pos.y, w: start.size.x, h: start.size.y },
      area,
    );
    return snapRect(fitted, area, SNAP_DISTANCE * ratio);
  };

  const shareHere = (rect: Rect | null): number =>
    column && rect ? dockShare(rect.h, column.h) : SHARE_DEFAULT;

  const pinFor = (): 'top' | 'bottom' | null =>
    dockTarget({ x: latest.x * ratio, y: latest.y * ratio }, column);

  const flush = () => {
    frame = 0;
    const rect = placedRect();
    if (!rect) {
      return;
    }
    const next = pinFor();
    const share = shareHere(rect);
    if (next !== hint || share !== hintShare) {
      hint = next;
      hintShare = share;
      handlers.onHint?.(next, share);
    }
    if (last && last.x === rect.x && last.y === rect.y) {
      return;
    }
    last = { x: rect.x, y: rect.y };
    Byond.winset(FLOAT_WINDOW, 'pos', `${rect.x},${rect.y}`);
  };

  const move = (e: PointerEvent) => {
    latest = { x: e.screenX, y: e.screenY };
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  };

  const end = () => {
    target.removeEventListener('pointermove', move);
    target.removeEventListener('pointerup', end);
    target.removeEventListener('pointercancel', end);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
    if (frame) {
      cancelAnimationFrame(frame);
    }
    flush();
    handlers.onHint?.(null);
    const pin = pinFor();
    console.log('chat layout: drag ended', {
      ratio,
      startMouse,
      latest,
      start,
      rect: placedRect(),
      area,
      column,
      pin,
      share: shareHere(placedRect()),
    });
    if (pin) {
      handlers.onPin(pin, shareHere(placedRect()));
    }
  };

  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  Promise.all([floatGeometry(), mainBounds()]).then(
    async ([geometry, main]) => {
      start = geometry;
      area = main?.visible ?? null;
      column = await measureColumn(main);
      console.log('chat layout: drag started', {
        ratio,
        startMouse,
        start,
        area,
        column,
      });
      if (frame === 0) {
        frame = requestAnimationFrame(flush);
      }
    },
  );
}

/**
 * Drags a docked chat by its tab row: past a small distance the chat pops out
 * into a float window under the pointer (onPopOut gets the pointer in physical
 * screen pixels). A plain click does nothing.
 */
export function startDockedDrag(
  event: React.PointerEvent<HTMLElement>,
  onPopOut: (pointer: Point) => void,
): void {
  if (event.button !== 0) {
    return;
  }
  const target = event.currentTarget;
  const pointer = event.pointerId;
  target.setPointerCapture(pointer);
  const ratio = pixelRatio();
  const startMouse: Point = { x: event.screenX, y: event.screenY };
  const stop = () => {
    target.removeEventListener('pointermove', move);
    target.removeEventListener('pointerup', stop);
    target.removeEventListener('pointercancel', stop);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
  };
  const move = (e: PointerEvent) => {
    const now = { x: e.screenX, y: e.screenY };
    if (!poppedOut(startMouse, now)) {
      return;
    }
    stop();
    const at = { x: Math.round(now.x * ratio), y: Math.round(now.y * ratio) };
    console.log('chat layout: popping out', { ratio, startMouse, now, at });
    onPopOut(at);
  };
  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', stop);
  target.addEventListener('pointercancel', stop);
}

/** Resizes the float window from its grip, with the same pointer capture. */
export function startWindowResize(
  event: React.PointerEvent<HTMLElement>,
): void {
  if (event.button !== 0) {
    return;
  }
  const target = event.currentTarget;
  const pointer = event.pointerId;
  target.setPointerCapture(pointer);
  const startMouse: Point = { x: event.screenX, y: event.screenY };
  const ratio = pixelRatio();
  let startSize: Point | null = null;
  let startPos: Point | null = null;
  let area: Rect | null = null;
  let latest: Point = startMouse;
  let frame = 0;

  const flush = () => {
    frame = 0;
    if (!startSize) {
      return;
    }
    const grown = resizeSize(startSize, startMouse, latest, ratio);
    const size = area && startPos ? fitSize(grown, startPos, area) : grown;
    Byond.winset(FLOAT_WINDOW, 'size', `${size.x}x${size.y}`);
  };

  const move = (e: PointerEvent) => {
    latest = { x: e.screenX, y: e.screenY };
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  };

  const end = () => {
    target.removeEventListener('pointermove', move);
    target.removeEventListener('pointerup', end);
    target.removeEventListener('pointercancel', end);
    if (target.hasPointerCapture(pointer)) {
      target.releasePointerCapture(pointer);
    }
    if (frame) {
      cancelAnimationFrame(frame);
    }
    flush();
  };

  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  Promise.all([floatGeometry(), mainBounds()]).then(([geometry, main]) => {
    startSize = geometry?.size ?? null;
    startPos = geometry?.pos ?? null;
    area = main?.visible ?? null;
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  });
}

/**
 * Puts the float window back inside the main window when any of it is outside
 * (the server places it at a default spot, and a maximized main window is
 * measured here, where the screen is known).
 */
export async function clampFloatToMain(): Promise<void> {
  const [geometry, main] = await Promise.all([floatGeometry(), mainBounds()]);
  if (!geometry || !main) {
    console.log('chat layout: float clamp skipped', { geometry, main });
    return;
  }
  const rect = fitRect(
    {
      x: geometry.pos.x,
      y: geometry.pos.y,
      w: geometry.size.x,
      h: geometry.size.y,
    },
    main.visible,
  );
  const moved =
    rect.x !== geometry.pos.x ||
    rect.y !== geometry.pos.y ||
    rect.w !== geometry.size.x ||
    rect.h !== geometry.size.y;
  console.log('chat layout: float clamp', {
    geometry,
    area: main.visible,
    rect,
    moved,
  });
  if (moved) {
    Byond.winset(FLOAT_WINDOW, {
      pos: `${rect.x},${rect.y}`,
      size: `${rect.w}x${rect.h}`,
    });
  }
}
