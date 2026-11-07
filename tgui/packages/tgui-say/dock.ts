import { createLogger } from 'tgui/logging';

const logger = createLogger('say-dock');

export type Rect = { x: number; y: number; w: number; h: number };

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

type Point = { x: number; y: number };

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

/**
 * Moves the popup to its dock for a window of the given native size; the
 * result is logged. Returns the position, or null when the map is unknown
 * (the window then stays where it was).
 */
export async function dockWindow(
  width: number,
  height: number,
): Promise<{ x: number; y: number } | null> {
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

/** Re-docks while the popup is open, so a resized or moved game window takes it along. Returns the stop function. */
export function watchDock(size: () => { w: number; h: number }): () => void {
  const timer = setInterval(async () => {
    const map = await measureMap();
    if (!map || sameRect(map, lastMap)) return;
    lastMap = map;
    const { w, h } = size();
    const pos = dockPosition(map, { w, h });
    Byond.winset(null, { 'tgui_say.pos': `${pos.x},${pos.y}` });
    logger.log('re-docked after map change', { map, window: { w, h }, pos });
  }, 500);
  return () => clearInterval(timer);
}
