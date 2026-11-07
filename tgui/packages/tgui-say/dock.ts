import { storage } from 'common/storage';
import { createLogger } from 'tgui/logging';

import {
  isReachable,
  minNativeSize,
  type Point,
  parseStoredPosition,
  type Rect,
  type Size,
  sizeToRestore,
  VIRTUAL_DESKTOP,
} from './placement';

export type { Rect } from './placement';

const logger = createLogger('say-dock');

const STORAGE_KEY = 'say-position';

/**
 * Native pixels kept clear along the bottom of the map for the hotbar rows
 * (two rows of 32px action buttons and their margins). The hotbar is drawn
 * by the map's own HUD, not a skin control, so its height cannot be read.
 */
export const HOTBAR_RESERVE = 80;

/** The popup's top-left so it is centred on the map, above the hotbar, never past the map's top-left. */
export function dockPosition(
  map: Rect,
  size: { w: number; h: number },
  reserve: number = HOTBAR_RESERVE,
): { x: number; y: number } {
  const x = map.x + Math.round((map.w - size.w) / 2);
  const y = map.y + map.h - reserve - size.h;
  return {
    x: Math.max(map.x, x),
    y: Math.max(map.y, y),
  };
}

const isPoint = (value: unknown): value is Point =>
  !!value &&
  typeof (value as Point).x === 'number' &&
  typeof (value as Point).y === 'number';

/** The map control's rectangle in screen pixels, or null when the client reports none. */
export async function measureMap(): Promise<Rect | null> {
  try {
    const [pos, size, inner, mapPos, mapSize] = await Promise.all([
      Byond.winget('mainwindow', 'pos'),
      Byond.winget('mainwindow', 'size'),
      Byond.winget('mainwindow', 'inner-size'),
      Byond.winget('map', 'pos'),
      Byond.winget('map', 'size'),
    ]);
    if (![pos, size, inner, mapPos, mapSize].every(isPoint)) {
      logger.warn('map geometry unavailable', {
        pos,
        size,
        inner,
        mapPos,
        mapSize,
      });
      return null;
    }
    // The frame around the client area: equal side borders, the rest is the title bar.
    const border = Math.max(0, Math.round((size.x - inner.x) / 2));
    const title = Math.max(0, size.y - inner.y - border);
    return {
      x: pos.x + border + mapPos.x,
      y: pos.y + title + mapPos.y,
      w: mapSize.x,
      h: mapSize.y,
    };
  } catch (error) {
    logger.error('map geometry query failed', error);
    return null;
  }
}

const sameRect = (a: Rect | null, b: Rect | null) =>
  !!a && !!b && a.x === b.x && a.y === b.y && a.w === b.w && a.h === b.h;

let lastMap: Rect | null = null;

/** The last measured map rectangle (null before the first measure). */
export function cachedMap(): Rect | null {
  return lastMap;
}

/** The position the player dragged the popup to (native screen pixels), or null while it follows the dock. */
let userPos: Point | null = null;
let placementLoaded: Promise<void> | null = null;

/** The player's saved position, read once from storage. */
export function loadPlacement(): Promise<void> {
  if (!placementLoaded) {
    placementLoaded = (async () => {
      try {
        userPos = parseStoredPosition(await storage.get(STORAGE_KEY));
        if (userPos) logger.log('restored player-placed position', userPos);
      } catch (error) {
        logger.error('failed to read saved position', error);
      }
    })();
  }
  return placementLoaded;
}

/** The saved position, null while docked. */
export function placedPosition(): Point | null {
  return userPos;
}

type ScreenDetails = {
  screens: { left: number; top: number; width: number; height: number }[];
};

let screensCache: Rect[] | null = null;

/** The monitors in native pixels when the client can list them, else the whole virtual desktop. */
async function screenRects(): Promise<Rect[]> {
  if (screensCache) return screensCache;
  try {
    const getDetails = (
      window as unknown as { getScreenDetails?: () => Promise<ScreenDetails> }
    ).getScreenDetails;
    if (getDetails) {
      const timeout = new Promise<null>((resolve) =>
        setTimeout(() => resolve(null), 500),
      );
      const details = await Promise.race([getDetails.call(window), timeout]);
      const ratio = window.devicePixelRatio || 1;
      if (details?.screens?.length) {
        const rects = details.screens.map((s) => ({
          x: s.left * ratio,
          y: s.top * ratio,
          w: s.width * ratio,
          h: s.height * ratio,
        }));
        screensCache = rects;
        return rects;
      }
    }
  } catch (error) {
    logger.warn('monitor list unavailable', error);
  }
  return [VIRTUAL_DESKTOP];
}

/** The player's position if still reachable; an unreachable one is dropped (and logged) so the popup docks. */
async function usablePlacement(size: Size): Promise<Point | null> {
  await loadPlacement();
  if (!userPos) return null;
  if (isReachable(userPos, size, await screenRects())) return userPos;
  logger.warn('saved position is off every screen; re-docking', {
    pos: userPos,
    size,
  });
  userPos = null;
  storage.remove(STORAGE_KEY);
  return null;
}

/** Remembers where the player left the popup, reading the position from the client. */
export async function rememberPlacement(): Promise<void> {
  try {
    const pos = await Byond.winget('tgui_say', 'pos');
    if (!isPoint(pos)) {
      logger.warn('could not read the dragged position', pos);
      return;
    }
    userPos = { x: Math.round(pos.x), y: Math.round(pos.y) };
    storage.set(STORAGE_KEY, userPos);
    logger.log('player placed the popup; auto-dock off', userPos);
  } catch (error) {
    logger.error('failed to save the dragged position', error);
  }
}

/** Back to the docked position: forgets the saved one and docks at the given native size. */
export async function resetPlacement(
  width: number,
  height: number,
): Promise<void> {
  const was = userPos;
  userPos = null;
  storage.remove(STORAGE_KEY);
  logger.log('player reset the popup to docked', { was });
  await dockWindow(width, height);
}

/**
 * Moves the popup to its place for a window of the given native size: where
 * the player left it, else the dock. Returns the position, or null when the
 * window stays where it was.
 */
export async function dockWindow(
  width: number,
  height: number,
): Promise<{ x: number; y: number } | null> {
  const placed = await usablePlacement({ w: width, h: height });
  if (placed) {
    Byond.winset(null, { 'tgui_say.pos': `${placed.x},${placed.y}` });
    return placed;
  }
  const map = await measureMap();
  if (!map) return null;
  const changed = !sameRect(map, lastMap);
  lastMap = map;
  const pos = dockPosition(map, { w: width, h: height });
  Byond.winset(null, { 'tgui_say.pos': `${pos.x},${pos.y}` });
  if (changed) {
    logger.log('docked', { map, window: { width, height }, pos });
  }
  return pos;
}

/**
 * The skin's resize message (interface/skin.dmf: `on-size` of the tgui_say window and of the map control run
 * `.output tgui_say.browser:update` with this type, client side, after a resize or splitter drag ends).
 */
export const DOCK_RESIZED = 'dock/resized';

/** The check of the open popup, or null while it is closed: what the resize message runs. */
let activeCheck: (() => Promise<void>) | null = null;
let subscribed = false;

/** Runs the open popup's check (the skin's resize message). Exported for the tests. */
export function onDockResized(): Promise<void> | undefined {
  return activeCheck?.();
}

/**
 * While the popup is open: keeps it at least the minimum size (a manual resize
 * below it is undone) and, until the player places it, re-docks it when the
 * map was resized (the game window or a splitter). Driven by the skin's on-size
 * events, not a timer. BYOND has no event for a window being moved (no
 * on-move), so moving the game window while the popup is open leaves it where
 * it is; the next open docks it again. Returns the stop function.
 */
export function watchDock(size: () => Size, factor: () => number): () => void {
  const check = async () => {
    try {
      const actual = await Byond.winget('tgui_say', 'size');
      if (isPoint(actual)) {
        const fix = sizeToRestore(
          { w: actual.x, h: actual.y },
          minNativeSize(factor()),
        );
        if (fix) {
          const sizeStr = `${fix.w}x${fix.h}`;
          Byond.winset(null, {
            'tgui_say.size': sizeStr,
            'tgui_say.browser.size': sizeStr,
          });
          logger.log('restored minimum size', { actual, fix });
        }
      }
    } catch (error) {
      logger.error('size check failed', error);
    }
    if (userPos) return;
    const map = await measureMap();
    if (!map || sameRect(map, lastMap)) return;
    lastMap = map;
    const { w, h } = size();
    const pos = dockPosition(map, { w, h });
    Byond.winset(null, { 'tgui_say.pos': `${pos.x},${pos.y}` });
    logger.log('re-docked after map change', { map, window: { w, h }, pos });
  };
  activeCheck = check;
  if (!subscribed) {
    subscribed = true;
    Byond.subscribeTo(DOCK_RESIZED, () => {
      onDockResized();
    });
  }
  return () => {
    if (activeCheck === check) activeCheck = null;
  };
}
