// In-game atom hover tooltip — TGUI.
//
// Hosted in the hidden mapwindow.tooltip BROWSER skin element. We SIZE THE
// BROWSER ELEMENT TO THE TOOLTIP BOX and park it at the cursor via Byond.winset,
// the way the legacy tooltip.html did. That's the only approach that doesn't
// block map clicks: a BROWSER control covering the map intercepts all mouse
// input at the control level (CSS pointer-events can't pass clicks through), so
// a full-map overlay eats every click. A box-sized element only covers the
// tooltip (which sits below the hovered tile and hides on MouseExited).
//
// Placement is done in a SINGLE winset (pos + size + is-visible) so the box
// appears already positioned — no top-left flash, no reposition jump. We measure
// the rendered box first (while still hidden when the engine allows it); if a
// hidden measure isn't available we show at the computed position — never the
// top-left — at a generous size and shrink to fit (the box is pinned to the
// element's top-left, so shrinking the element doesn't move it).
//
// We render a bare <div>, not a tgui <Window> (its Layout chrome paints opaque
// theme backgrounds). TOOLTIP_RESET_CSS zeroes the page so only the box paints.

import { useEffect, useRef } from 'react';
import { useBackend } from 'tgui/backend';
import type { BooleanLike } from 'tgui-core/react';
import { HtmlRenderer } from './common/HtmlRenderer';

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

export const Tooltip = () => {
  const { data } = useBackend<Data>();
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const winId = data.control || Byond.windowId;

    if (!data.visible) {
      Byond.winset(winId, { 'is-visible': false });
      return;
    }

    let cancelled = false;

    Promise.all([
      // Byond.winget returns {x, y} objects (not "WxH" strings):
      //   size      = the map control's pixel dimensions
      //   view-size = the rendered map content's pixel size (letterboxed inside
      //               the control when aspect ratios differ)
      Byond.winget('mapwindow.map', 'size'),
      Byond.winget('mapwindow.map', 'view-size'),
    ])
      .then(([rawSize, rawViewSize]: any[]) => {
        if (cancelled) return;

        const mapPxW = Number(rawSize?.x) || 0;
        const mapPxH = Number(rawSize?.y) || 0;
        const renderedW = Number(rawViewSize?.x) || 0;
        const renderedH = Number(rawViewSize?.y) || 0;
        const tilesShownX = data.view_w;
        const tilesShownY = data.view_h;

        // Compute the box's top-left in map pixels. Best-effort: if anything is
        // missing, fall back to the map's top-left rather than mis-placing.
        let posX = 4;
        let posY = 4;
        let perTileY = 0;

        if (mapPxW && mapPxH && renderedW && renderedH && tilesShownX && tilesShownY) {
          const realIconSizeX = renderedW / tilesShownX;
          const realIconSizeY = renderedH / tilesShownY;
          perTileY = realIconSizeY;
          const resizeRatioX = realIconSizeX / data.tile_size;
          const resizeRatioY = realIconSizeY / data.tile_size;

          // Letterbox bars between the control and the rendered map content.
          let leftOffset = (mapPxW - renderedW) / 2;
          let topOffset = (mapPxH - renderedH) / 2;

          // Parse cursor params: "icon-x=NN;icon-y=NN;screen-loc=X:px,Y:py"
          const params = parseSemiParams(data.cursor_params);
          const iconX = parseInt(params['icon-x'] ?? '0', 10);
          const iconY = parseInt(params['icon-y'] ?? '0', 10);
          const screenLocRaw = params['screen-loc'] ?? '';
          const [leftRaw, topRaw] = screenLocRaw.split(',');

          if (leftRaw && topRaw) {
            const [leftTileStr, enteredXStr] = leftRaw.split(':');
            const [topTileStr, enteredYStr] = topRaw.split(':');
            let left = parseInt(leftTileStr ?? '0', 10);
            let top = parseInt(topTileStr ?? '0', 10);
            const enteredX = parseInt(enteredXStr ?? '0', 10);
            const enteredY = parseInt(enteredYStr ?? '0', 10);

            // The atom's own screen_loc may carry pixel offsets like "WEST+0:6".
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

            posX = Math.round((left - 1) * realIconSizeX + leftOffset + 2);
            posY = Math.round(
              (tilesShownY - top + 1) * realIconSizeY + topOffset + 2,
            );
          }
        }

        // Position + size + show in one winset so the box appears already placed.
        // Box is pinned to the element's top-left, so a later shrink never moves it.
        const placeAndShow = (w: number, h: number) => {
          let py = posY;
          if (mapPxH && py + h > mapPxH) {
            py = Math.max(0, posY - h - Math.round(perTileY) - 4);
          }
          Byond.winset(winId, {
            pos: `${Math.max(0, posX)},${py}`,
            size: `${w}x${h}`,
            'is-visible': true,
          });
        };

        const box = boxRef.current;
        const w0 = Math.ceil(box?.offsetWidth || 0);
        const h0 = Math.ceil(box?.offsetHeight || 0);
        if (w0 > 0 && h0 > 0) {
          // Measured while hidden — appear already positioned and sized.
          placeAndShow(w0, h0);
        } else {
          // Hidden layout unavailable: show at the computed position (NOT the
          // top-left) at a generous size, then shrink to fit on the next frame.
          Byond.winset(winId, {
            pos: `${Math.max(0, posX)},${posY}`,
            size: '300x340',
            'is-visible': true,
          });
          requestAnimationFrame(() => {
            if (cancelled) return;
            const b = boxRef.current;
            placeAndShow(
              Math.ceil(b?.offsetWidth || 0) || 80,
              Math.ceil(b?.offsetHeight || 0) || 24,
            );
          });
        }
      })
      .catch(() => {
        // winget can fail mid-shutdown; just leave the element hidden.
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
  // the element viewport.
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
