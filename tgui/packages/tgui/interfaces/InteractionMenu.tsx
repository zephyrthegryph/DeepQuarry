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
import { CONSOLE_THEME } from 'tgui/layouts/consoleTheme';
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
  role?: string | null;
  distance?: string | null;
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
`;

const MAX_HEIGHT = 420;

/** "ROLE // DISTANCE", whichever halves the server sent. */
export const menuSubtitle = (
  role?: string | null,
  distance?: string | null,
): string =>
  [role, distance]
    .filter((part): part is string => !!part)
    .map((part) => part.toUpperCase())
    .join(' // ');

/** The short label of a basic action button ("Point at" is "Point"). */
export const actionLabel = (name: string): string => name.replace(/ at$/i, '');

export const InteractionMenu = () => {
  const { act, data } = useBackend<Data>();
  const boxRef = useRef<HTMLDivElement>(null);
  const {
    target,
    role,
    distance,
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

  // The popup is a bare page (no <Window>), so it takes the console theme the way Layout does.
  useEffect(() => {
    document.documentElement.className = `theme-${CONSOLE_THEME}`;
  }, []);

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
      <div ref={boxRef} className="InteractionMenu">
        <div className="InteractionMenu__header">
          <div className="InteractionMenu__heading">
            <div className="InteractionMenu__name">{target || 'Nothing'}</div>
            {!!target && (
              <div className="InteractionMenu__subtitle">
                {menuSubtitle(role, distance)}
              </div>
            )}
          </div>
          <button
            type="button"
            className="InteractionMenu__close"
            onClick={() => act('close')}
          >
            ×
          </button>
        </div>
        {target && nothing && (
          <div className="InteractionMenu__blocked">Nothing to do here.</div>
        )}
        {(available.length > 0 || blocked.length > 0) && (
          <div className="InteractionMenu__rows">
            {available.map((entry) => (
              <button
                type="button"
                key={entry.id}
                className="InteractionMenu__row"
                title={entry.desc ?? undefined}
                onClick={() => act('run', { id: entry.id })}
              >
                <span>{`> ${entry.name}`}</span>
                {!!entry.keys?.[0] && (
                  <span className="InteractionMenu__key">{entry.keys[0]}</span>
                )}
              </button>
            ))}
            {blocked.map((entry) => (
              <div
                key={entry.id}
                className="InteractionMenu__blocked"
                title={entry.reason || entry.desc || undefined}
              >
                {`x ${entry.name}`}
                {!!entry.reason && (
                  <span className="InteractionMenu__reason">
                    {` [${entry.reason.toUpperCase()}]`}
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
        {target && actions.length > 0 && (
          <div className="InteractionMenu__actions">
            {actions.map((entry) => (
              <button
                type="button"
                key={entry.id}
                className="InteractionMenu__action"
                onClick={() => act('action', { id: entry.id })}
              >
                {actionLabel(entry.name)}
              </button>
            ))}
          </div>
        )}
        {target && verbs.length > 0 && (
          <div className="InteractionMenu__rows InteractionMenu__verbs">
            {verbs.map((name) => (
              <button
                type="button"
                key={name}
                className="InteractionMenu__row"
                onClick={() => act('verb', { name })}
              >
                <span>{`> ${name}`}</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
