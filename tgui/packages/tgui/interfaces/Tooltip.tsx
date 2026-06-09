// In-game atom hover tooltip — TGUI.
//
// Hosted inside the hidden 999x999 mainwindow.tooltip BROWSER skin
// element. The element is shown/hidden by DM via winset. While shown
// this React tree renders an absolutely-positioned tooltip <div>
// inside the otherwise transparent (pointer-events: none) layer, so
// clicks pass straight through to the underlying map.
//
// Ports the positioning math from the legacy tooltip.html JS: query
// the live map element pixel size via Byond.winget, then map the
// cursor's icon-x/icon-y + screen-loc to overlay pixels.

import { useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import type { BooleanLike } from 'tgui-core/react';
import { HtmlRenderer } from './common/HtmlRenderer';

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

type Position = { x: number; y: number } | null;

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
  const [position, setPosition] = useState<Position>(null);

  useEffect(() => {
    if (!data.visible) {
      setPosition(null);
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

        // Letterboxing offset between the BROWSER element (full
        // mainwindow) and the actual map content.
        let leftOffset = (999 - mapPxW) / 2;
        let topOffset = (999 - mapPxH) / 2;

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

        // Position the tooltip just below the hovered tile.
        const posX = Math.round((left - 1) * realIconSizeX + leftOffset + 2);
        const posY = Math.round(
          (tilesShownY - top + 1) * realIconSizeY + topOffset + 2,
        );

        setPosition({ x: posX, y: posY });
      })
      .catch(() => {
        // winget can fail mid-shutdown; just leave position null and
        // the tooltip won't render.
      });

    return () => {
      cancelled = true;
    };
  }, [
    data.visible,
    data.cursor_params,
    data.screen_loc,
    data.view_w,
    data.view_h,
    data.tile_size,
  ]);

  // theme="tooltip" makes the outer Window transparent (see main.scss). Without
  // it the standard .Window grey background fills the full-window 999x999 browser
  // element and paints a grey box over the viewport whenever the element is shown.
  if (!data.visible || !position) {
    return <Window fitted theme="tooltip" />;
  }

  const themeStyle = themeStyles[data.theme] ?? themeStyles.default;

  return (
    <Window fitted theme="tooltip">
      <div
        // Root layer is transparent and passes clicks through to the
        // map underneath; only the inner tooltip box catches events.
        style={{
          position: 'fixed',
          inset: 0,
          pointerEvents: 'none',
        }}
      >
        <div
          style={{
            position: 'absolute',
            left: position.x,
            top: position.y,
            maxWidth: 298,
            padding: 8,
            border: `2px solid ${themeStyle.borderColor}`,
            color: themeStyle.color,
            backgroundColor: themeStyle.backgroundColor,
            font: 'bold 12px Arial, "Helvetica Neue", Helvetica, sans-serif',
            pointerEvents: 'auto',
          }}
        >
          <HtmlRenderer html={data.title} />
        </div>
      </div>
    </Window>
  );
};
