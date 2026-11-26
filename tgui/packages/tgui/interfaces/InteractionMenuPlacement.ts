// Where the interaction menu opens: the cursor of the click that opened it,
// in the map element's own pixels. Pure math, so it is tested without BYOND.
//
// The map shows viewW x viewH tiles. With icon-size 0 (Fit Viewport / stretch)
// the view is scaled up to fit the control, keeping its aspect ratio and centred
// (letterboxed); with a fixed icon-size N each tile is N pixels. The scale is
// derived from those two settings and the control size, never from the control's
// "view-size" property, whose meaning under stretch is not the scaled picture.

export type MapGeometry = {
  mapW: number;
  mapH: number;
  /** The control's icon-size: 0 stretches the view to fit. */
  iconSize: number;
  viewW: number;
  viewH: number;
  /** world.icon_size, the pixels per tile the screen-loc pixel offsets use. */
  tileSize: number;
};

export const parseSemiParams = (s: string): Record<string, string> => {
  const out: Record<string, string> = {};
  for (const part of (s || '').split(/[;&]/)) {
    if (!part) continue;
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    const raw = part.slice(eq + 1);
    try {
      out[part.slice(0, eq)] = decodeURIComponent(raw);
    } catch {
      out[part.slice(0, eq)] = raw;
    }
  }
  return out;
};

/** Device pixels per native pixel, and the picture's size and offset inside the control. */
export const mapScale = (g: MapGeometry) => {
  const tile = g.tileSize || 32;
  const nativeW = g.viewW * tile;
  const nativeH = g.viewH * tile;
  const scale =
    g.iconSize > 0
      ? g.iconSize / tile
      : Math.min(g.mapW / nativeW, g.mapH / nativeH);
  const renderedW = nativeW * scale;
  const renderedH = nativeH * scale;
  return {
    scale,
    renderedW,
    renderedH,
    left: (g.mapW - renderedW) / 2,
    top: (g.mapH - renderedH) / 2,
  };
};

/** One screen-loc axis: "tile" or "tile:pixel" (the x axis of a secondary map is "map:tile:pixel"). */
const axis = (raw: string, fromEnd: boolean): [number, number] | null => {
  const parts = raw.split(':');
  const hasPixel = parts.length >= 2;
  const tileStr = fromEnd && hasPixel ? parts[parts.length - 2] : parts[0];
  const pixelStr = fromEnd ? parts[parts.length - 1] : parts[1];
  const tile = parseInt(tileStr ?? '', 10);
  if (Number.isNaN(tile)) return null;
  const pixel = hasPixel ? parseInt(pixelStr ?? '', 10) : 0;
  return [tile, Number.isNaN(pixel) ? 0 : pixel];
};

/** The cursor position inside the map element in device pixels, or null when the click carried none. */
export const cursorInMap = (
  cursorParams: string,
  g: MapGeometry,
): [number, number] | null => {
  const screenLoc = parseSemiParams(cursorParams)['screen-loc'] ?? '';
  const [xRaw, yRaw] = screenLoc.split(',');
  if (!xRaw || !yRaw || !g.viewW || !g.viewH || !g.mapW || !g.mapH) {
    return null;
  }
  const xs = axis(xRaw, true);
  const ys = axis(yRaw, false);
  if (!xs || !ys) return null;
  // A tile outside the view is not a position inside the map: no cursor, not a clamp to a wall.
  if (xs[0] < 1 || ys[0] < 1 || xs[0] > g.viewW || ys[0] > g.viewH) return null;
  const tile = g.tileSize || 32;
  const { scale, left, top } = mapScale(g);
  // Pixel offsets inside a tile run 1..tile from the left and from the bottom.
  const inTileX = Math.max(0, xs[1] - 1);
  const inTileY = Math.max(0, ys[1] - 1);
  const x = left + ((xs[0] - 1) * tile + inTileX) * scale;
  const y = top + ((g.viewH - ys[0]) * tile + (tile - 1 - inTileY)) * scale;
  return [Math.round(x), Math.round(y)];
};

/**
 * Top left of a w x h menu opened at the cursor: down and right of it, flipped
 * to the other side at the map's right and bottom edges, then clamped inside.
 */
export const placeMenu = (
  cursor: [number, number],
  w: number,
  h: number,
  mapW: number,
  mapH: number,
): [number, number] => {
  let px = cursor[0];
  let py = cursor[1];
  if (px + w > mapW) px -= w;
  if (py + h > mapH) py -= h;
  px = Math.max(0, Math.min(px, mapW - w));
  py = Math.max(0, Math.min(py, mapH - h));
  return [Math.round(px), Math.round(py)];
};
