// The Inspect panel: examining anything fills it (code/content/examine/inspect_panel.dm).
//
// Like the interaction menu it is hosted in a browser element of the map pane (mapwindow.inspect_panel), not a
// separate window: we measure the box, size the element to it and put it in the top right corner of the map in
// ONE winset, so it appears already placed. It renders a bare <div> rather than a tgui <Window> and takes the
// console theme the way Layout does. The close button or Escape hides it; examining something shows it again.

import { useEffect, useRef, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { CONSOLE_THEME } from 'tgui/layouts/consoleTheme';
import type { BooleanLike } from 'tgui-core/react';
import { HtmlRenderer } from './common/HtmlRenderer';
import {
  type Chip,
  chipText,
  chipTone,
  clampPanelSize,
  inspectSubtitle,
  panelWidth,
  placeTopRight,
} from './InspectPanelLogic';

type Worn = { slot: string; name: string; ref: string };

type Tab = { ref: string; name: string; active: BooleanLike };

type Data = {
  visible: BooleanLike;
  control: string;
  view_w: number;
  view_h: number;
  tile_size: number;
  revision: number;
  target: string | null;
  kind?: string | null;
  role?: string | null;
  distance?: string | null;
  description?: string[];
  notes?: [string, string][];
  worn?: Worn[];
  body?: Chip[];
  tabs?: Tab[];
  portrait?: string | null;
  flavor?: string | null;
  show_flavor?: BooleanLike;
  has_ooc?: BooleanLike;
  primary?: { id: string; name: string } | null;
};

const PANEL_RESET_CSS = `
html, body, #react-root, .InspectPanelRoot,
div[class^="theme-"], .Layout, .Layout__content, .Window {
  background: transparent !important;
  background-image: none !important;
  margin: 0 !important;
  padding: 0 !important;
  border: 0 !important;
  overflow: hidden !important;
}
html, body, #react-root, .InspectPanelRoot {
  position: fixed !important;
  inset: 0 !important;
}
`;

/** The panel's css width (InspectPanel.scss) and its gap to the map's corner. */
const PANEL_CSS_WIDTH = 400;
const MARGIN = 10;
const MAX_HEIGHT = 560;

type Size = { w: number; h: number };

export const InspectPanel = () => {
  const { act, data } = useBackend<Data>();
  const boxRef = useRef<HTMLDivElement>(null);
  // The size the player dragged the panel to (css pixels), kept across examines; null until they drag.
  const [userSize, setUserSize] = useState<Size | null>(null);
  const userSizeRef = useRef<Size | null>(null);
  const mapRef = useRef<[number, number]>([0, 0]);
  const {
    target,
    kind,
    role,
    distance,
    description = [],
    notes = [],
    worn = [],
    body = [],
    tabs = [],
    portrait,
    flavor,
    show_flavor,
    has_ooc,
    primary,
  } = data;

  // Place and show (or hide) the element whenever the server examines something or hides us.
  useEffect(() => {
    const winId = data.control || Byond.windowId;
    if (!data.visible) {
      Byond.winset(winId, { 'is-visible': false });
      return;
    }
    let cancelled = false;
    Byond.winget('mapwindow.map', 'size')
      .then((rawSize: any) => {
        if (cancelled) return;
        const mapW = Number(rawSize?.x) || 0;
        const mapH = Number(rawSize?.y) || 0;
        if (!mapW || !mapH) {
          return;
        }
        mapRef.current = [mapW, mapH];
        const pixelRatio = window.devicePixelRatio || 1;
        const sized = userSizeRef.current;
        if (sized) {
          // The player chose a size: keep it rather than fitting the content.
          const pw = Math.ceil(sized.w * pixelRatio);
          const [px, py] = placeTopRight(pw, mapW, MARGIN * pixelRatio);
          Byond.winset(winId, {
            pos: `${px},${py}`,
            size: `${pw}x${Math.ceil(sized.h * pixelRatio)}`,
            'is-visible': true,
          });
          return;
        }
        // Measure after this revision has rendered.
        requestAnimationFrame(() => {
          if (cancelled) return;
          const box = boxRef.current;
          const w = panelWidth(PANEL_CSS_WIDTH, pixelRatio, mapW);
          const h = Math.min(
            Math.ceil(
              Math.min(box?.scrollHeight || 200, MAX_HEIGHT) * pixelRatio,
            ),
            mapH,
          );
          const [px, py] = placeTopRight(w, mapW, MARGIN * pixelRatio);
          Byond.winset(winId, {
            pos: `${px},${py}`,
            size: `${w}x${h}`,
            'is-visible': true,
          });
        });
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
    data.revision,
    data.view_w,
    data.view_h,
    data.tile_size,
    target,
    description.length,
    worn.length,
    body.length,
    show_flavor,
  ]);

  // Drag the bottom left corner to resize: the panel is anchored to the map's top right, so it grows leftwards
  // and downwards. The element is resized as the pointer moves.
  const startResize = (event: React.PointerEvent<HTMLDivElement>) => {
    const box = boxRef.current;
    const [mapW, mapH] = mapRef.current;
    if (!box || !mapW || !mapH) {
      return;
    }
    event.preventDefault();
    const handle = event.currentTarget;
    handle.setPointerCapture(event.pointerId);
    const pixelRatio = window.devicePixelRatio || 1;
    const startX = event.clientX;
    const startY = event.clientY;
    const startW = box.offsetWidth;
    const startH = box.offsetHeight;
    const winId = data.control || Byond.windowId;
    const onMove = (move: PointerEvent) => {
      const [w, h] = clampPanelSize(
        startW + (startX - move.clientX),
        startH + (move.clientY - startY),
        mapW / pixelRatio,
        mapH / pixelRatio,
        MARGIN,
      );
      const next = { w, h };
      userSizeRef.current = next;
      setUserSize(next);
      const pw = Math.ceil(w * pixelRatio);
      const [px, py] = placeTopRight(pw, mapW, MARGIN * pixelRatio);
      Byond.winset(winId, {
        pos: `${px},${py}`,
        size: `${pw}x${Math.ceil(h * pixelRatio)}`,
      });
    };
    const onUp = () => {
      handle.removeEventListener('pointermove', onMove);
      handle.removeEventListener('pointerup', onUp);
      handle.removeEventListener('pointercancel', onUp);
    };
    handle.addEventListener('pointermove', onMove);
    handle.addEventListener('pointerup', onUp);
    handle.addEventListener('pointercancel', onUp);
  };

  // The panel is a bare page (no <Window>), so it takes the console theme the way Layout does.
  useEffect(() => {
    document.documentElement.className = `theme-${CONSOLE_THEME}`;
  }, []);

  // Escape closes the panel.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        act('close');
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <div className="InspectPanelRoot">
      <style>{PANEL_RESET_CSS}</style>
      <div
        ref={boxRef}
        className="InspectPanel"
        style={
          userSize
            ? { width: `${userSize.w}px`, height: `${userSize.h}px` }
            : undefined
        }
      >
        <div
          className="InspectPanel__resize"
          title="Drag to resize"
          onPointerDown={startResize}
        />
        <div className="InspectPanel__header">
          <div className="InspectPanel__heading">
            <div className="InspectPanel__name">
              {`INSPECT // ${target || 'Nothing'}`}
            </div>
            {!!target && (
              <div className="InspectPanel__subtitle">
                {inspectSubtitle(kind, role, distance)}
              </div>
            )}
          </div>
          <button
            type="button"
            className="InspectPanel__close"
            onClick={() => act('close')}
          >
            ×
          </button>
        </div>
        {tabs.length > 1 && (
          <div className="InspectPanel__tabs">
            {tabs.map((tab) => (
              <button
                type="button"
                key={tab.ref}
                title={tab.name}
                className={`InspectPanel__tab${tab.active ? ' InspectPanel__tab--active' : ''}`}
                onClick={() => act('select', { ref: tab.ref })}
              >
                {tab.name.toUpperCase()}
              </button>
            ))}
          </div>
        )}
        {!!target && (
          <div className="InspectPanel__body">
            <div className="InspectPanel__main">
              {description.map((line, index) => (
                <div key={index} className="InspectPanel__text">
                  <HtmlRenderer html={line} />
                </div>
              ))}
              {notes.map(([title, text]) => (
                <div key={title} className="InspectPanel__note">
                  <span className="InspectPanel__noteTitle">{`${title}: `}</span>
                  <HtmlRenderer html={text} />
                </div>
              ))}
              {worn.length > 0 && (
                <>
                  <div className="InspectPanel__heading2">&gt; WORN</div>
                  <div className="InspectPanel__worn">
                    {worn.map((row) => (
                      <WornRow
                        key={`${row.slot}:${row.ref}`}
                        row={row}
                        onInspect={() => act('inspect', { ref: row.ref })}
                      />
                    ))}
                  </div>
                </>
              )}
              {body.length > 0 && (
                <>
                  <div className="InspectPanel__heading2">&gt; BODY</div>
                  <div className="InspectPanel__chips">
                    {body.map((chip, index) => (
                      <span
                        key={index}
                        className={`InspectPanel__chip InspectPanel__chip--${chipTone(chip.tone)}`}
                      >
                        {chipText(chip)}
                      </span>
                    ))}
                  </div>
                </>
              )}
              {!!show_flavor && !!flavor && (
                <div className="InspectPanel__note">
                  <HtmlRenderer html={flavor} />
                </div>
              )}
            </div>
            <div className="InspectPanel__side">
              <div className="InspectPanel__portrait">
                {!!portrait && (
                  <img alt="" src={`data:image/png;base64,${portrait}`} />
                )}
              </div>
              <button
                type="button"
                className="InspectPanel__button InspectPanel__button--small"
                onClick={() => act('turn')}
              >
                ⟲ TURN
              </button>
            </div>
          </div>
        )}
        {!!target && (!!flavor || !!has_ooc || !!primary) && (
          <div className="InspectPanel__buttons">
            {(!!flavor || !!has_ooc) && (
              <div className="InspectPanel__row">
                {!!flavor && (
                  <button
                    type="button"
                    className="InspectPanel__button"
                    onClick={() => act('flavor')}
                  >
                    ≡ Flavor Text
                  </button>
                )}
                {!!has_ooc && (
                  <button
                    type="button"
                    className="InspectPanel__button"
                    onClick={() => act('ooc')}
                  >
                    ≡ OOC Notes
                  </button>
                )}
              </div>
            )}
            {!!primary && (
              <button
                type="button"
                className="InspectPanel__button InspectPanel__button--primary"
                onClick={() => act('primary', { id: primary.id })}
              >
                {`> ${primary.name}`}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
};

const WornRow = (props: { row: Worn; onInspect: () => void }) => (
  <>
    <span className="InspectPanel__slot">{props.row.slot}</span>
    <button
      type="button"
      className="InspectPanel__item"
      onClick={props.onInspect}
    >
      {props.row.name}
    </button>
  </>
);
