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
// Flow each show: make the element visible at a tiny size FIRST (so its page is
// laid out and measurable, and so it always appears even if the positioning math
// below can't run), then measure the rendered box and winset the element to the
// box's exact size + the cursor position. Positioning is best-effort: any missing
// winget/param value falls back to the map's top-left rather than hiding.
//
// We render a bare <div>, not a tgui <Window> (its Layout chrome paints opaque
// theme backgrounds). The box fills the element; TOOLTIP_RESET_CSS zeroes body
// margins so the box sits flush at 0,0.

import { useEffect, useRef } from 'react';
import { useBackend } from 'tgui/backend';
import type { BooleanLike } from 'tgui-core/react';
import { HtmlRenderer } from './common/HtmlRenderer';

// Neutralize the tgui base/theme chrome (opaque backgrounds + body margin) so the
// box sits flush at the element's 0,0; the element is sized to the box so the
// page is otherwise not visible.
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
  // Explicit skin element id ("mapwindow.tooltip"). We winset this rather than
  // Byond.windowId, which may not resolve to the element for this child window.
  control: string;
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
    // Prefer the explicit element id from DM; fall back to Byond.windowId.
    const winId = data.control || Byond.windowId;

    if (!data.visible) {
      Byond.winset(winId, { 'is-visible': false });
      return;
    }

    let cancelled = false;

    // Show immediately (tiny) so the element is visible + its page laid out for
    // measuring, regardless of whether the positioning math below succeeds.
    Byond.winset(winId, { size: '8x8', 'is-visible': true });

    // Measure the rendered box and winset the element to it at (posX, posY).
    const place = (posX: number, posY: number, mapPxH: number, perTileY: number) => {
      requestAnimationFrame(() => {
        if (cancelled) return;
        const box = boxRef.current;
        const w = Math.ceil(box?.offsetWidth || 0) || 80;
        const h = Math.ceil(box?.offsetHeight || 0) || 24;
        let py = posY;
        if (mapPxH && py + h > mapPxH) {
          py = Math.max(0, posY - h - Math.round(perTileY) - 4);
        }
        const px = Math.max(0, posX);
        Byond.winset(winId, { pos: `${px},${py}`, size: `${w}x${h}` });
      });
    };

    Promise.all([
      Byond.winget('mapwindow.map', 'size'),
      Byond.winget('mapwindow.map', 'view-size'),
    ])
      .then(([rawSize, rawViewSize]) => {
        if (cancelled) return;
        const [mapPxW, mapPxH] = parseMapSize(rawSize);
        const [mapTileW, mapTileH] = parseMapSize(rawViewSize);
        const tilesShownX = data.view_w || mapTileW;
        const tilesShownY = data.view_h || mapTileH;

        // Best-effort: missing map metrics -> park at the map's top-left.
        if (!mapPxW || !mapPxH || !tilesShownX || !tilesShownY) {
          place(4, 4, mapPxH, 0);
          return;
        }

        const realIconSizeX = mapPxW / tilesShownX;
        const realIconSizeY = mapPxH / tilesShownY;
        const resizeRatioX = realIconSizeX / data.tile_size;
        const resizeRatioY = realIconSizeY / data.tile_size;

        let leftOffset = 0;
        let topOffset = 0;

        const params = parseSemiParams(data.cursor_params);
        const iconX = parseInt(params['icon-x'] ?? '0', 10);
        const iconY = parseInt(params['icon-y'] ?? '0', 10);
        const screenLocRaw = params['screen-loc'] ?? '';
        const [leftRaw, topRaw] = screenLocRaw.split(',');
        if (!leftRaw || !topRaw) {
          place(4, 4, mapPxH, realIconSizeY);
          return;
        }

        const [leftTileStr, enteredXStr] = leftRaw.split(':');
        const [topTileStr, enteredYStr] = topRaw.split(':');
        let left = parseInt(leftTileStr ?? '0', 10);
        let top = parseInt(topTileStr ?? '0', 10);
        const enteredX = parseInt(enteredXStr ?? '0', 10);
        const enteredY = parseInt(enteredYStr ?? '0', 10);

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

        left = Math.max(0, Math.min(tilesShownX, left));
        top = Math.max(0, Math.min(tilesShownY, top));

        const posX = Math.round((left - 1) * realIconSizeX + leftOffset + 2);
        const posY = Math.round(
          (tilesShownY - top + 1) * realIconSizeY + topOffset + 2,
        );

        place(posX, posY, mapPxH, realIconSizeY);
      })
      .catch(() => {
        if (!cancelled) place(4, 4, 0, 0);
      });

    return () => {
      cancelled = true;
    };
  }, [
    data.visible,
    data.control,
    data.title,
    data.cursor_params,
    data.screen_loc,
    data.view_w,
    data.view_h,
    data.tile_size,
  ]);

  const themeStyle = themeStyles[data.theme] ?? themeStyles.default;

  // The box is always rendered flush at the element's top-left; the effect sizes
  // the element to it. width: max-content keeps its measured size independent of
  // the (transiently tiny) element viewport.
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
