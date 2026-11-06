// The interaction menu: the right-click popup (code/datums/interactions/menu.dm).
//
// Like BYOND's native verb popup it opens at the cursor. It is hosted in the
// hidden mapwindow.interaction_menu BROWSER element (a map child, like the
// hover tooltip), not in a separate window: we measure the rendered rows, size
// the element to them and place it at the clicked pixel in ONE winset (pos +
// size + is-visible), so it appears already placed. The cursor math is in
// InteractionMenuPlacement.ts: tile -> pixel through the map's icon-size (0 =
// stretched to fit, letterboxed), plus the pixel inside the tile.
//
// It renders a bare <div> rather than a tgui <Window> (whose chrome paints a
// full window). Picking a row, the close button, Escape or the next click on the
// map hide it.

import { useEffect, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import type { BooleanLike } from 'tgui-core/react';
import { cursorInMap, placeMenu } from './InteractionMenuPlacement';

type Available = {
  id: string;
  name: string;
  desc?: string | null;
  category: string | null;
  keys: string[];
};

type Blocked = {
  id: string;
  name: string;
  desc?: string | null;
  category: string | null;
  reason: string;
};

type Hidden = {
  id: string;
  name: string;
  hidden_by: string;
};

type Action = {
  id: string;
  name: string;
};

type Data = {
  visible: BooleanLike;
  control: string;
  cursor_params: string;
  view_w: number;
  view_h: number;
  tile_size: number;
  revision: number;
  target: string | null;
  available?: Available[];
  blocked?: Blocked[];
  actions?: Action[];
  verbs?: string[];
  /** Staff only (R_DEBUG or R_ADMIN): the rows left out, with the requirement that left each out. */
  hidden?: Hidden[] | null;
};

const MENU_RESET_CSS = `
html, body, #react-root, .InteractionMenuRoot,
div[class^="theme-"], .Layout, .Layout__content, .Window {
  background: transparent !important;
  background-image: none !important;
  margin: 0 !important;
  padding: 0 !important;
  border: 0 !important;
  overflow: hidden !important;
}
html, body, #react-root, .InteractionMenuRoot {
  position: fixed !important;
  inset: 0 !important;
}
.InteractionMenu__row {
  display: block;
  width: 100%;
  padding: 2px 10px;
  border: 0;
  background: transparent;
  color: #e6e6e6;
  text-align: left;
  font: 12px Verdana, Geneva, sans-serif;
  white-space: nowrap;
  cursor: pointer;
}
.InteractionMenu__row:hover {
  background: #3e6189;
  color: #ffffff;
}
.InteractionMenu__blocked {
  padding: 2px 10px;
  color: #7a7a7a;
  font: 12px Verdana, Geneva, sans-serif;
  white-space: nowrap;
}
.InteractionMenu__separator {
  height: 1px;
  margin: 3px 4px;
  background: #4a4a4a;
}
.InteractionMenu__title {
  display: flex;
  padding: 3px 4px 3px 10px;
  color: #9fb4cc;
  font: bold 12px Verdana, Geneva, sans-serif;
  white-space: nowrap;
}
`;

const MAX_HEIGHT = 420;

export const InteractionMenu = () => {
  const { act, data } = useBackend<Data>();
  const boxRef = useRef<HTMLDivElement>(null);
  const {
    target,
    available = [],
    blocked = [],
    actions = [],
    verbs = [],
    hidden = null,
  } = data;
  const [showHidden, setShowHidden] = useState(false);

  // Place and show (or hide) the element whenever the server opens or hides us.
  useEffect(() => {
    const winId = data.control || Byond.windowId;
    if (!data.visible) {
      Byond.winset(winId, { 'is-visible': false });
      return;
    }
    let cancelled = false;
    Promise.all([
      Byond.winget('mapwindow.map', 'size'),
      Byond.winget('mapwindow.map', 'icon-size'),
    ])
      .then(([rawSize, rawIconSize]: any[]) => {
        if (cancelled) return;
        const mapW = Number(rawSize?.x) || 0;
        const mapH = Number(rawSize?.y) || 0;
        const iconSize = Number(rawIconSize) || 0;
        if (!mapW || !mapH || !data.view_w || !data.view_h) {
          return;
        }
        const pixelRatio = window.devicePixelRatio || 1;
        const place = () => {
          if (cancelled) return;
          const box = boxRef.current;
          const w = Math.min(
            Math.ceil(((box?.scrollWidth || 200) + 2) * pixelRatio),
            mapW,
          );
          const h = Math.min(
            Math.ceil(
              Math.min(box?.scrollHeight || 120, MAX_HEIGHT) * pixelRatio,
            ),
            mapH,
          );
          const cursor = cursorInMap(data.cursor_params, {
            mapW,
            mapH,
            iconSize,
            viewW: data.view_w,
            viewH: data.view_h,
            tileSize: data.tile_size,
          }) ?? [Math.round((mapW - w) / 2), Math.round((mapH - h) / 2)];
          // Open down and right of the cursor, flipped and clamped at the map's edges, as the native popup does.
          const [px, py] = placeMenu(cursor, w, h, mapW, mapH);
          Byond.winset(winId, {
            pos: `${px},${py}`,
            size: `${w}x${h}`,
            'is-visible': true,
            focus: true,
          });
        };
        // Measure after the rows for this revision have rendered.
        requestAnimationFrame(place);
      })
      .catch(() => {
        // winget can fail mid-shutdown; leave the element hidden.
      });
    return () => {
      cancelled = true;
    };
  }, [
    data.visible,
    data.control,
    data.cursor_params,
    data.revision,
    data.view_w,
    data.view_h,
    data.tile_size,
    target,
  ]);

  // Escape closes the popup.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        act('close');
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const nothing =
    available.length === 0 &&
    blocked.length === 0 &&
    actions.length === 0 &&
    verbs.length === 0;

  return (
    <div className="InteractionMenuRoot">
      <style>{MENU_RESET_CSS}</style>
      <div
        ref={boxRef}
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          width: 'max-content',
          minWidth: 140,
          maxWidth: 320,
          maxHeight: MAX_HEIGHT,
          overflowY: 'auto',
          padding: '2px 0',
          border: '1px solid #5a5a5a',
          backgroundColor: '#252525',
          boxShadow: '2px 2px 4px rgba(0, 0, 0, 0.5)',
          boxSizing: 'border-box',
        }}
      >
        <div className="InteractionMenu__title">
          <span style={{ flexGrow: 1, overflow: 'hidden' }}>
            {target || 'Nothing'}
          </span>
          <button
            type="button"
            className="InteractionMenu__row"
            style={{ width: 'auto', padding: '0 4px' }}
            onClick={() => act('close')}
          >
            ×
          </button>
        </div>
        {hidden && (
          <button
            type="button"
            className="InteractionMenu__row"
            onClick={() => setShowHidden(!showHidden)}
          >
            {showHidden ? 'Hide hidden' : `Show hidden (${hidden.length})`}
          </button>
        )}
        {hidden &&
          showHidden &&
          hidden.map((entry) => (
            <div
              key={`hidden-${entry.id}`}
              className="InteractionMenu__blocked"
              title={entry.hidden_by}
            >
              {entry.name} [hidden by {entry.hidden_by}]
            </div>
          ))}
        {target && nothing && (
          <div className="InteractionMenu__blocked">Nothing to do here.</div>
        )}
        {available.map((entry) => (
          <button
            type="button"
            key={entry.id}
            className="InteractionMenu__row"
            title={entry.desc ?? undefined}
            onClick={() => act('run', { id: entry.id })}
          >
            {entry.name}
          </button>
        ))}
        {blocked.map((entry) => (
          <div
            key={entry.id}
            className="InteractionMenu__blocked"
            title={entry.reason || entry.desc || undefined}
          >
            {entry.name}
            {entry.reason ? ` (${entry.reason})` : ''}
          </div>
        ))}
        {target && actions.length > 0 && (
          <div className="InteractionMenu__separator" />
        )}
        {target &&
          actions.map((entry) => (
            <button
              type="button"
              key={entry.id}
              className="InteractionMenu__row"
              onClick={() => act('action', { id: entry.id })}
            >
              {entry.name}
            </button>
          ))}
        {target && verbs.length > 0 && (
          <div className="InteractionMenu__separator" />
        )}
        {target &&
          verbs.map((name) => (
            <button
              type="button"
              key={name}
              className="InteractionMenu__row"
              onClick={() => act('verb', { name })}
            >
              {name}
            </button>
          ))}
      </div>
    </div>
  );
};
