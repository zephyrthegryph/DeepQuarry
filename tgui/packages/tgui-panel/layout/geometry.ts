import {
  type ChatMode,
  chatHeightInColumn,
  columnRect,
  dockShare,
  dockTarget,
  dragPosition,
  fitBrowserSize,
  fitRect,
  MAP_SPLIT_MAX,
  MAP_SPLIT_MIN,
  type MainReport,
  mainRects,
  mapSplitFromX,
  type Point,
  poppedOut,
  type Rect,
  type ResizeEdges,
  resizeRect,
  SHARE_DEFAULT,
  SNAP_DISTANCE,
  shareFromHeights,
  shareFromY,
  snapRect,
  splitBorderX,
  splitterFor,
} from './model';

/** The skin's float window and the right-hand split (SKIN_CHAT_FLOAT_WINDOW, SKIN_RPANE_SPLIT). */
const FLOAT_WINDOW = 'chat_float';
const COLUMN_SPLIT = 'rpane.rpanewindow';
/** The main window's split between the map and the right-hand column (SKIN_MAIN_SPLIT). */
const MAIN_SPLIT = 'mainwindow.mainvsplit';

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

/** The screen x of the splitter between the map and the right-hand column, or null when it cannot be told. */
async function measureSplitBorder(main: Bounds | null): Promise<number | null> {
  if (!main) {
    return null;
  }
  try {
    const got = await Byond.winget(MAIN_SPLIT, ['size', 'splitter']);
    const percent = Number(got?.splitter);
    if (!isPoint(got?.size) || !Number.isFinite(percent)) {
      return null;
    }
    return splitBorderX(main.client, got.size.x, percent);
  } catch {
    return null;
  }
}

export type DragHandlers = {
  /** The pin a drop would make right now, while dragging (null when none). */
  onHint?: (hint: 'top' | 'bottom' | null, share?: number) => void;
  /** The drop landed over the right-hand column: dock there. */
  onPin: (mode: ChatMode, share: number) => void;
};

type DragSession = {
  /** Where the mouse was when the drag began, in CSS screen pixels. */
  startMouse: Point;
  /** Receives the pointer events: the strip (captured) or, for a resumed drag, the window. */
  target: EventTarget;
  pointerId: number;
  /** A drag carried over from a pop-out: the first move must have the button down. */
  resumed?: boolean;
  /** Takes pointer capture on the strip (the resumed drag does this on its first move). */
  capture?: (pointerId: number) => void;
  release?: () => void;
};

/**
 * Drags the float window with the mouse, with no OS title bar: the window
 * position follows the mouse deltas in physical pixels (winset pos), held in
 * the main window's client area and snapped to its edges and to the border
 * between the map and the right-hand column. Dropping with the pointer over
 * that column docks the chat there, the upper half to the top and the lower
 * half to the bottom; the hint shows that target while dragging.
 */
function runWindowDrag(session: DragSession, handlers: DragHandlers): void {
  const { startMouse, target, pointerId } = session;
  const ratio = pixelRatio();
  let start: { pos: Point; size: Point } | null = null;
  let area: Rect | null = null;
  let column: Rect | null = null;
  let borderX: number | null = null;
  let latest: Point = startMouse;
  let frame = 0;
  let last: Point | null = null;
  let hint: 'top' | 'bottom' | null = null;
  let hintShare = 0;
  let live = !session.resumed;
  let finished = false;
  let giveUp: ReturnType<typeof setTimeout> | undefined;

  const placedRect = (): Rect | null => {
    if (!start) {
      return null;
    }
    const pos = dragPosition(start.pos, startMouse, latest, ratio);
    const fitted = fitRect(
      { x: pos.x, y: pos.y, w: start.size.x, h: start.size.y },
      area,
    );
    return snapRect(
      fitted,
      area,
      SNAP_DISTANCE * ratio,
      borderX === null ? {} : { x: [borderX] },
    );
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

  const schedule = () => {
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  };

  const detach = () => {
    target.removeEventListener('pointermove', move as EventListener);
    target.removeEventListener('pointerup', end);
    target.removeEventListener('pointercancel', end);
    clearTimeout(giveUp);
    session.release?.();
  };

  const move = (e: PointerEvent) => {
    if (!live) {
      // The first move of a resumed drag: the button must still be down, else the player let go before the window showed.
      if (!(e.buttons & 1)) {
        console.log('chat layout: resumed drag dropped, button is up', {
          buttons: e.buttons,
        });
        finished = true;
        detach();
        return;
      }
      live = true;
      console.log('chat layout: drag resumed in the float window', {
        pointer: pointerId,
        id: e.pointerId,
        buttons: e.buttons,
      });
      session.capture?.(e.pointerId);
    }
    latest = { x: e.screenX, y: e.screenY };
    schedule();
  };

  const end = () => {
    if (finished) {
      return;
    }
    finished = true;
    detach();
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
      borderX,
      pin,
      share: shareHere(placedRect()),
    });
    if (pin) {
      handlers.onPin(pin, shareHere(placedRect()));
    }
  };

  target.addEventListener('pointermove', move as EventListener);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  if (session.resumed) {
    // Nothing moved in the new window in time: the drag is over.
    giveUp = setTimeout(() => {
      if (!live && !finished) {
        console.log('chat layout: resumed drag timed out');
        finished = true;
        detach();
      }
    }, RESUME_WINDOW_MS);
  }
  Promise.all([floatGeometry(), mainBounds()]).then(
    async ([geometry, main]) => {
      start = geometry;
      area = main?.visible ?? null;
      column = await measureColumn(main);
      borderX = await measureSplitBorder(main);
      console.log('chat layout: drag started', {
        ratio,
        startMouse,
        start,
        area,
        column,
        borderX,
        resumed: !!session.resumed,
      });
      if (live) {
        schedule();
      }
    },
  );
}

/** Starts dragging the float window from its strip (pointer captured by the strip). */
export function startWindowDrag(
  event: React.PointerEvent<HTMLElement>,
  handlers: DragHandlers,
): void {
  if (event.button !== 0) {
    return;
  }
  const strip = event.currentTarget;
  const pointer = event.pointerId;
  strip.setPointerCapture(pointer);
  runWindowDrag(
    {
      startMouse: { x: event.screenX, y: event.screenY },
      target: strip,
      pointerId: pointer,
      release: () => {
        if (strip.hasPointerCapture(pointer)) {
          strip.releasePointerCapture(pointer);
        }
      },
    },
    handlers,
  );
}

/** How long a pop-out waits for the mouse to show up in the float window before the drag is dropped. */
const RESUME_WINDOW_MS = 5000;

/** The mouse of a pop-out whose drag has not yet been picked up by the float window (CSS screen pixels). */
let pendingResume: { mouse: Point; at: number } | null = null;

/**
 * Carries the drag of a pop-out into the float window. Moving the pane to its
 * own window re-parents the browser and drops its pointer capture, but the
 * page stays the same page and the button is still down: the drag continues
 * from the window's own pointer events (the first move must have the button
 * held) with no new click.
 */
export function resumePopoutDrag(handlers: DragHandlers): void {
  const pending = pendingResume;
  pendingResume = null;
  if (!pending || Date.now() - pending.at > RESUME_WINDOW_MS) {
    console.log('chat layout: no pop-out drag to resume', { pending });
    return;
  }
  runWindowDrag(
    {
      startMouse: pending.mouse,
      target: window,
      pointerId: -1,
      resumed: true,
      capture: (id) => {
        // Best effort: capture on the strip keeps the moves coming when the window outruns the pointer.
        const strip = document.querySelector('.ChatDragRow');
        if (strip) {
          try {
            (strip as HTMLElement).setPointerCapture(id);
          } catch (error) {
            console.log('chat layout: capture after pop-out refused', error);
          }
        }
      },
    },
    handlers,
  );
}

/**
 * Drags a docked chat by its tab row: past a small distance the chat pops out
 * into a float window under the pointer (onPopOut gets the pointer in physical
 * screen pixels) and the drag carries on there (resumePopoutDrag). A plain
 * click does nothing.
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
    pendingResume = { mouse: now, at: Date.now() };
    console.log('chat layout: popping out', {
      ratio,
      startMouse,
      now,
      at,
      buttons: e.buttons,
    });
    onPopOut(at);
  };
  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', stop);
  target.addEventListener('pointercancel', stop);
}

/**
 * Resizes the float window from one of its edges or corners (page-drawn
 * handles: the window has no OS frame). Position and size go in one winset, so
 * a left or top edge moves the window as it grows; the rect stays inside the
 * main window's client area and above the minimum size. If BYOND ignores the
 * size of a window that cannot resize, the window is allowed to resize for the
 * duration of the drag.
 */
export function startWindowResize(
  event: React.PointerEvent<HTMLElement>,
  edges: ResizeEdges,
): void {
  if (event.button !== 0) {
    return;
  }
  event.stopPropagation();
  const target = event.currentTarget;
  const pointer = event.pointerId;
  target.setPointerCapture(pointer);
  const startMouse: Point = { x: event.screenX, y: event.screenY };
  const ratio = pixelRatio();
  let startRect: Rect | null = null;
  let area: Rect | null = null;
  let latest: Point = startMouse;
  let frame = 0;
  let applied: Rect | null = null;
  let verified = false;
  let resizable = false;

  const apply = (rect: Rect) => {
    Byond.winset(FLOAT_WINDOW, {
      pos: `${rect.x},${rect.y}`,
      size: `${rect.w}x${rect.h}`,
    });
  };

  const flush = () => {
    frame = 0;
    if (!startRect) {
      return;
    }
    const rect = resizeRect(startRect, edges, startMouse, latest, ratio, area);
    if (
      applied &&
      applied.x === rect.x &&
      applied.y === rect.y &&
      applied.w === rect.w &&
      applied.h === rect.h
    ) {
      return;
    }
    applied = rect;
    apply(rect);
    if (!verified) {
      verified = true;
      setTimeout(async () => {
        const got = await floatGeometry();
        const want = applied;
        if (!got || !want) {
          return;
        }
        const ignored =
          Math.abs(got.size.x - want.w) > 2 ||
          Math.abs(got.size.y - want.h) > 2;
        console.log('chat layout: resize check', { want, got, ignored });
        if (ignored && !resizable) {
          resizable = true;
          console.log(
            'chat layout: BYOND ignored the size; allowing resize for this drag',
          );
          Byond.winset(FLOAT_WINDOW, 'can-resize', 'true');
          apply(want);
        }
      }, 120);
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
    if (resizable) {
      Byond.winset(FLOAT_WINDOW, 'can-resize', 'false');
    }
    console.log('chat layout: resize ended', {
      edges,
      startRect,
      rect: applied,
      area,
    });
  };

  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  Promise.all([floatGeometry(), mainBounds()]).then(([geometry, main]) => {
    startRect = geometry
      ? {
          x: geometry.pos.x,
          y: geometry.pos.y,
          w: geometry.size.x,
          h: geometry.size.y,
        }
      : null;
    area = main?.visible ?? null;
    console.log('chat layout: resize started', { edges, startRect, area });
    if (!frame) {
      frame = requestAnimationFrame(flush);
    }
  });
}

/** Which border a drag of the pinned chat's edge moves. */
export type SplitKind = 'column' | 'map';

/** Splitter updates go out at most this often while dragging (about 30 per second). */
export const SPLIT_INTERVAL_MS = 33;

/**
 * Drags a splitter live: the chat/stat split of the right-hand column (the
 * chat's edge) or the split between the map and the column. BYOND's own
 * splitter only applies on release, so the page draws the handle and sets the
 * splitter itself, at most every SPLIT_INTERVAL_MS, then reports the final
 * value (onDone) so the server remembers it.
 */
export function startSplitDrag(
  event: React.PointerEvent<HTMLElement>,
  kind: SplitKind,
  mode: ChatMode,
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
  let ctx: { column: Rect | null; main: Bounds | null; width: number } | null =
    null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let lastAt = 0;
  let lastValue: number | null = null;

  const valueNow = (): number | null => {
    if (!ctx) {
      return null;
    }
    const px = { x: latest.x * ratio, y: latest.y * ratio };
    if (kind === 'map') {
      return ctx.main ? mapSplitFromX(ctx.main.client, ctx.width, px.x) : null;
    }
    return ctx.column ? shareFromY(mode, ctx.column, px.y) : null;
  };

  const push = (): number | null => {
    timer = undefined;
    const value = valueNow();
    if (value === null || value === lastValue) {
      return value;
    }
    lastValue = value;
    lastAt = performance.now();
    if (kind === 'map') {
      Byond.winset(MAIN_SPLIT, 'splitter', `${value}`);
    } else {
      Byond.winset(COLUMN_SPLIT, 'splitter', `${splitterFor(mode, value)}`);
    }
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
    console.log('chat layout: split drag ended', { kind, mode, value });
    if (value !== null) {
      onDone(value);
    }
  };

  target.addEventListener('pointermove', move);
  target.addEventListener('pointerup', end);
  target.addEventListener('pointercancel', end);
  mainBounds().then(async (main) => {
    const column = await measureColumn(main);
    let width = 0;
    try {
      const got = await Byond.winget(MAIN_SPLIT, 'size');
      width = isPoint(got) ? got.x : 0;
    } catch {
      width = 0;
    }
    ctx = { column, main, width };
    console.log('chat layout: split drag started', {
      kind,
      mode,
      column,
      width,
      client: main?.client,
    });
    schedule();
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

const OUTPUT_PANE = 'output_browser';
const CHAT_BROWSER = 'browseroutput';
const FLOAT_HOST = 'chat_float_host';

/**
 * Sizes the chat browser to the space it really has, once the layout settles
 * (on start and whenever the server moves the pane). The anchors keep it right
 * through every later resize, so nothing runs on a window resize. The pane
 * window's own size can be stale (a pane that was hidden keeps the size it
 * had), which left the page taller than the column and past the screen bottom;
 * so the size is held to what the host (the chat's part of the column, or the
 * float window) reports.
 */
export async function fitChatBrowser(
  mode: ChatMode,
  reason: string,
): Promise<void> {
  try {
    const pane = await Byond.winget(OUTPUT_PANE, 'size');
    if (!isPoint(pane)) {
      console.log('chat layout: fit skipped, pane size unknown', {
        reason,
        pane,
      });
      return;
    }
    let expected: Point | null = null;
    if (mode === 'float') {
      const host = await Byond.winget(FLOAT_HOST, 'size');
      expected = isPoint(host) ? host : null;
    } else {
      const got = await Byond.winget(COLUMN_SPLIT, ['size', 'splitter']);
      const splitter = Number(got?.splitter);
      if (isPoint(got?.size) && Number.isFinite(splitter)) {
        expected = {
          x: got.size.x,
          y: chatHeightInColumn(mode, got.size.y, splitter),
        };
      }
    }
    const size = fitBrowserSize(pane, expected);
    console.log('chat layout: fit chat browser', {
      reason,
      mode,
      pane,
      expected,
      size,
    });
    Byond.winset(CHAT_BROWSER, { pos: '0,0', size: `${size.x}x${size.y}` });
  } catch (error) {
    console.log('chat layout: fit chat browser failed', { reason, error });
  }
}
