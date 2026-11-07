import {
  type ChatMode,
  clientRect,
  columnRect,
  dockTarget,
  dragPosition,
  fitSize,
  looseFit,
  type Point,
  poppedOut,
  type Rect,
  resizeSize,
  shareFromHeights,
  trustedArea,
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

type Bounds = { outer: Rect; client: Rect };

/**
 * The main window's outer rect and client area in screen pixels: what a drag
 * is kept near, and where the right-hand column is.
 */
export async function mainBounds(): Promise<Bounds | null> {
  try {
    const got = await Byond.winget('mainwindow', ['pos', 'outer-size', 'size']);
    const client = isPoint(got?.size) ? got.size : null;
    const outerSize = isPoint(got?.['outer-size']) ? got['outer-size'] : client;
    if (!isPoint(got?.pos) || !outerSize || !client || outerSize.x <= 0) {
      console.log('chat layout: main window bounds unknown', got);
      return null;
    }
    const outer = {
      x: got.pos.x,
      y: got.pos.y,
      w: outerSize.x,
      h: outerSize.y,
    };
    const bounds = { outer, client: clientRect(outer, client) };
    console.log('chat layout: main window', {
      got,
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

type DragHandlers = {
  /** The pin a drop would make right now, while dragging (null when none). */
  onHint?: (hint: 'top' | 'bottom' | null) => void;
  /** The drop landed over the right-hand column: dock there. */
  onPin: (mode: ChatMode) => void;
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

  const placedRect = (): Rect | null => {
    if (!start) {
      return null;
    }
    const pos = dragPosition(start.pos, startMouse, latest, ratio);
    return looseFit(
      { x: pos.x, y: pos.y, w: start.size.x, h: start.size.y },
      area,
    );
  };

  const pinFor = (): 'top' | 'bottom' | null =>
    dockTarget({ x: latest.x * ratio, y: latest.y * ratio }, column);

  const flush = () => {
    frame = 0;
    const rect = placedRect();
    if (!rect) {
      return;
    }
    const next = pinFor();
    if (next !== hint) {
      hint = next;
      handlers.onHint?.(next);
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
    });
    if (pin) {
      handlers.onPin(pin);
    }
  };

  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  Promise.all([floatGeometry(), mainBounds()]).then(
    async ([geometry, main]) => {
      start = geometry;
      const startRect = geometry
        ? {
            x: geometry.pos.x,
            y: geometry.pos.y,
            w: geometry.size.x,
            h: geometry.size.y,
          }
        : null;
      area = trustedArea(main?.outer ?? null, startRect);
      if (main && !area) {
        console.log(
          'chat layout: main window does not hold the float window; the drag is not limited by it',
          { outer: main.outer, startRect },
        );
      }
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
    area = main?.outer ?? null;
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  });
}
