// In-game atom hover tooltip — TGUI.
//
// Hosted in the hidden mapwindow.tooltip BROWSER skin element. Unlike a normal
// tgui window we SIZE THE BROWSER ELEMENT TO THE TOOLTIP BOX and park it at the
// cursor via Byond.winset, the way the legacy tooltip.html did.
//
// This is the only approach that doesn't block map clicks: a BROWSER control
// covering the map intercepts all mouse input at the control level — CSS
// pointer-events can't pass clicks through to the map behind it — so a full-map
// overlay, even a transparent one, eats every click. By shrinking the element to
// the box it only ever covers the small tooltip (which sits below the hovered
// tile and hides on MouseExited), leaving the rest of the map clickable.
//
// We render a bare <div>, not a tgui <Window> (its Layout chrome paints opaque
// theme backgrounds). The box fills the element; TOOLTIP_RESET_CSS zeroes body
// margins so the box sits flush at 0,0 and keeps the page transparent so any
// sub-pixel gap shows the map rather than grey.
//
// Positioning math is ported from the legacy tooltip.html JS: query the live map
// element pixel size via Byond.winget, then map the cursor's icon-x/icon-y +
// screen-loc to map pixels for the element's pos.

import { useEffect, useRef } from 'react';
import { useBackend } from 'tgui/backend';
import type { BooleanLike } from 'tgui-core/react';
import { HtmlRenderer } from './common/HtmlRenderer';

// Neutralize the tgui base/theme chrome (which would otherwise leave opaque
// pixels and a body margin) so the box sits flush at the element's 0,0 and any
// gap shows the map (the element has inner-background-color=#00000000 in BYOND).
const TOOLTIP_RESET_CSS = `
html, body, #react-root, .TooltipRoot,
div[class^="theme-"], .Layout, .Layout__content, .Window {
  background: transparent !important;
  background-image: none !important;
  margin: 0 !important;
  padding: 0 !important;
  border: 0 !important;
  overflow: visible !important;
}
html, body, #react-root, .TooltipRoot {
  position: fixed !important;
  inset: 0 !important;
}
`;

type Data = {
  visible: BooleanLike;
  title: string;
  content: string;
  theme: string;
  cursor_params: string;
  screen_loc: string;
  view_w: number;
  view_h: number;
  tile_size: number;
};

const themeStyles: Record<string, React.CSSProperties> = {
  midnight: {
    color: '#6087a0',
    borderColor: '#2b2b33',
    backgroundColor: '#36363c',
  },
  plasmafire: {
    color: '#ffa800',
    borderColor: '#21213d',
    backgroundColor: '#1d1d36',
  },
  retro: {
    color: '#003366',
    borderColor: '#005e00',
    backgroundColor: '#00bd00',
  },
  slimecore: {
    color: '#6ea161',
    borderColor: '#11450b',
    backgroundColor: '#354e35',
  },
  operative: {
    color: '#b01232',
    borderColor: '#13121b',
    backgroundColor: '#282831',
  },
  clockwork: {
    color: '#b18b25',
    borderColor: '#000000',
    backgroundColor: '#5f380e',
  },
  default: {
    color: '#ffffff',
    borderColor: '#0033cc',
    backgroundColor: '#005cb8',
  },
};

const parseSemiParams = (s: string): Record<string, string> => {
  const out: Record<string, string> = {};
  for (const part of s.split(';')) {
    if (!part) continue;
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    out[part.slice(0, eq)] = part.slice(eq + 1);
  }
  return out;
};

const parseMapSize = (raw: string | undefined): [number, number] => {
  if (!raw) return [0, 0];
  // BYOND returns sizes as "WxH"
  const [w, h] = raw.split('x').map((v) => parseInt(v.trim(), 10));
  return [w || 0, h || 0];
};

export const Tooltip = () => {
  const { data } = useBackend<Data>();
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!data.visible) {
      Byond.winset(Byond.windowId, { 'is-visible': false });
      return;
    }

    let cancelled = false;

    Promise.all([
      // Byond.winget for the live pixel size of the map element.
      // `size` is the pixel size; `view-size` is the BYOND tile size.
      Byond.winget('mapwindow.map', 'size'),
      Byond.winget('mapwindow.map', 'view-size'),
    ])
      .then(([rawSize, rawViewSize]) => {
        if (cancelled) return;
        const [mapPxW, mapPxH] = parseMapSize(rawSize);
        const [mapTileW, mapTileH] = parseMapSize(rawViewSize);
        if (!mapPxW || !mapPxH || !mapTileW || !mapTileH) return;

        const tilesShownX = data.view_w || mapTileW;
        const tilesShownY = data.view_h || mapTileH;
        if (!tilesShownX || !tilesShownY) return;

        // Real per-tile pixel size of the rendered map and resize ratio
        // vs the engine's tile size (data.tile_size).
        const realIconSizeX = mapPxW / tilesShownX;
        const realIconSizeY = mapPxH / tilesShownY;
        const resizeRatioX = realIconSizeX / data.tile_size;
        const resizeRatioY = realIconSizeY / data.tile_size;

        // The element is a mapwindow child positioned in map-pixel space, so no
        // full-window centering offset is needed; offsets only accumulate the
        // atom's own screen_loc pixel offsets below.
        let leftOffset = 0;
        let topOffset = 0;

        // Parse cursor params: "icon-x=NN;icon-y=NN;screen-loc=X:px,Y:py"
        const params = parseSemiParams(data.cursor_params);
        const iconX = parseInt(params['icon-x'] ?? '0', 10);
        const iconY = parseInt(params['icon-y'] ?? '0', 10);
        const screenLocRaw = params['screen-loc'] ?? '';
        if (!iconX || !iconY || !screenLocRaw) return;

        const [leftRaw, topRaw] = screenLocRaw.split(',');
        if (!leftRaw || !topRaw) return;

        const [leftTileStr, enteredXStr] = leftRaw.split(':');
        const [topTileStr, enteredYStr] = topRaw.split(':');
        let left = parseInt(leftTileStr ?? '0', 10);
        let top = parseInt(topTileStr ?? '0', 10);
        const enteredX = parseInt(enteredXStr ?? '0', 10);
        const enteredY = parseInt(enteredYStr ?? '0', 10);

        // Original (atom) screen_loc, used to compute offsets when the
        // atom's screen_loc itself has a pixel offset like "WEST+0:6".
        const oScreenLoc = data.screen_loc.split(',');
        if (oScreenLoc[0]) {
          const westParts = oScreenLoc[0].split(':');
          if (westParts.length > 1) {
            const westOffset = parseInt(westParts[1], 10);
            if (westOffset !== 0) {
              if (iconX + westOffset !== enteredX) {
                left += westOffset < 0 ? 1 : -1;
              }
              leftOffset += westOffset * resizeRatioX;
            }
          }
        }
        if (oScreenLoc.length > 1) {
          const northParts = oScreenLoc[1].split(':');
          if (northParts.length > 1) {
            const northOffset = parseInt(northParts[1], 10);
            if (northOffset !== 0) {
              if (iconY + northOffset === enteredY) {
                top--;
                topOffset -= (data.tile_size + northOffset) * resizeRatioY;
              } else if (northOffset < 0) {
                topOffset -= (data.tile_size + northOffset) * resizeRatioY;
              } else {
                top--;
                topOffset -= northOffset * resizeRatioY;
              }
            }
          }
        }

        // Clamp.
        left = Math.max(0, Math.min(tilesShownX, left));
        top = Math.max(0, Math.min(tilesShownY, top));

        // Top-left where the box should sit (just below the hovered tile).
        const posX = Math.round((left - 1) * realIconSizeX + leftOffset + 2);
        const posY = Math.round(
          (tilesShownY - top + 1) * realIconSizeY + topOffset + 2,
        );

        // Measure the rendered box, size the element to it, park it at the
        // cursor. offsetWidth/Height are border-box (incl. border+padding) since
        // the box is box-sizing: border-box; the box fills the element 1:1.
        const box = boxRef.current;
        if (!box) return;
        const w = Math.ceil(box.offsetWidth) || 64;
        const h = Math.ceil(box.offsetHeight) || 24;

        // Flip above the tile if the box would run off the bottom of the map.
        let py = posY;
        if (py + h > mapPxH) {
          py = Math.max(0, posY - h - Math.round(realIconSizeY) - 4);
        }
        // Keep it inside the map horizontally.
        const px = Math.max(0, Math.min(posX, Math.max(0, mapPxW - w)));

        Byond.winset(Byond.windowId, {
          pos: `${px},${py}`,
          size: `${w}x${h}`,
          'is-visible': true,
        });
      })
      .catch(() => {
        // winget can fail mid-shutdown; just leave the element hidden.
      });

    return () => {
      cancelled = true;
    };
  }, [
    data.visible,
    data.title,
    data.cursor_params,
    data.screen_loc,
    data.view_w,
    data.view_h,
    data.tile_size,
  ]);

  const themeStyle = themeStyles[data.theme] ?? themeStyles.default;

  // The box is always rendered flush at the element's top-left; the effect sizes
  // the element to it. width: max-content makes its measured size independent of
  // the (transiently small) element viewport.
  return (
    <div className="TooltipRoot">
      <style>{TOOLTIP_RESET_CSS}</style>
      <div
        ref={boxRef}
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          width: 'max-content',
          maxWidth: 298,
          padding: 8,
          border: `2px solid ${themeStyle.borderColor}`,
          color: themeStyle.color,
          backgroundColor: themeStyle.backgroundColor,
          font: 'bold 12px Arial, "Helvetica Neue", Helvetica, sans-serif',
          boxSizing: 'border-box',
        }}
      >
        <HtmlRenderer html={data.title} />
      </div>
    </div>
  );
};
