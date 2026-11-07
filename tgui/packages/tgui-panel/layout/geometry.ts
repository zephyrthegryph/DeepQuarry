import {
  type ChatMode,
  dragPosition,
  type Point,
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

/** The main window's place: what a pin snaps to. */
async function mainArea(): Promise<Rect | null> {
  try {
    const got = await Byond.winget('mainwindow', ['pos', 'size']);
    return isPoint(got?.pos) && isPoint(got?.size)
      ? { x: got.pos.x, y: got.pos.y, w: got.size.x, h: got.size.y }
      : null;
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

  const placed = (): Point | null =>
    start ? dragPosition(start.pos, startMouse, latest, ratio) : null;

  const flush = () => {
    frame = 0;
    const pos = placed();
    if (!pos || (last && last.x === pos.x && last.y === pos.y)) {
      return;
    }
    last = pos;
    Byond.winset(FLOAT_WINDOW, 'pos', `${pos.x},${pos.y}`);
    if (start && area) {
      handlers.onHint?.(
        snapTarget(
          { x: pos.x, y: pos.y, w: start.size.x, h: start.size.y },
          area,
        ),
      );
    }
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
    const pos = placed();
    if (pos && start && area) {
      const pin = snapTarget(
        { x: pos.x, y: pos.y, w: start.size.x, h: start.size.y },
        area,
      );
      if (pin) {
        handlers.onPin(pin);
      }
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
  let latest: Point = startMouse;
  let frame = 0;

  const flush = () => {
    frame = 0;
    if (!startSize) {
      return;
    }
    const size = resizeSize(startSize, startMouse, latest, ratio);
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
  floatGeometry().then((geometry) => {
    startSize = geometry?.size ?? null;
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  });
}
