import {
  type ChatMode,
  dragPosition,
  fitRect,
  fitSize,
  type Point,
  pointerSnap,
  type Rect,
  resizeSize,
  shareFromHeights,
  snapTarget,
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

/**
 * The main window's place and outer size in screen pixels: the area the float
 * window must stay inside, and what a pin snaps to.
 */
export async function mainArea(): Promise<Rect | null> {
  try {
    const got = await Byond.winget('mainwindow', ['pos', 'outer-size', 'size']);
    const size = isPoint(got?.['outer-size']) ? got['outer-size'] : got?.size;
    if (!isPoint(got?.pos) || !isPoint(size) || size.x <= 0 || size.y <= 0) {
      console.log('chat layout: main window bounds unknown', got);
      return null;
    }
    return { x: got.pos.x, y: got.pos.y, w: size.x, h: size.y };
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
  /** A pin the drop would make, while dragging (null when none). */
  onHint?: (hint: 'top' | 'bottom' | null) => void;
  /** The drop landed near the right edge: pin there. */
  onPin: (mode: ChatMode) => void;
};

/**
 * Drags the float window with the mouse, with no OS title bar: the pointer is
 * captured by the strip, the window position follows the mouse deltas in
 * physical pixels (winset pos), and a drop near the main window's right edge
 * pins the chat to the top or the bottom of the column.
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
  let latest: Point = startMouse;
  let frame = 0;
  let last: Point | null = null;

  /** The window rect for the latest mouse place, held inside the main window. */
  const placedRect = (): Rect | null => {
    if (!start) {
      return null;
    }
    const pos = dragPosition(start.pos, startMouse, latest, ratio);
    const rect = { x: pos.x, y: pos.y, w: start.size.x, h: start.size.y };
    return area ? fitRect(rect, area) : rect;
  };

  /** The pin the latest mouse place asks for: the pointer in the right strip, or the window against the right edge. */
  const pinFor = (rect: Rect): 'top' | 'bottom' | null => {
    if (!area) {
      return null;
    }
    const pointer = { x: latest.x * ratio, y: latest.y * ratio };
    return pointerSnap(pointer, area) ?? snapTarget(rect, area);
  };

  const flush = () => {
    frame = 0;
    const rect = placedRect();
    if (!rect || (last && last.x === rect.x && last.y === rect.y)) {
      return;
    }
    last = { x: rect.x, y: rect.y };
    Byond.winset(FLOAT_WINDOW, 'pos', `${rect.x},${rect.y}`);
    handlers.onHint?.(pinFor(rect));
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
    const rect = placedRect();
    const pin = rect ? pinFor(rect) : null;
    console.log('chat layout: drag ended', { rect, area, pin });
    if (pin) {
      handlers.onPin(pin);
    }
  };

  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  Promise.all([floatGeometry(), mainArea()]).then(([geometry, main]) => {
    start = geometry;
    area = main;
    if (frame === 0) {
      frame = requestAnimationFrame(flush);
    }
  });
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
  Promise.all([floatGeometry(), mainArea()]).then(([geometry, main]) => {
    startSize = geometry?.size ?? null;
    startPos = geometry?.pos ?? null;
    area = main;
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  });
}
