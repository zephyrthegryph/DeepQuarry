// The Inspect panel logic (interfaces/InspectPanel.tsx): the subtitle, chips and where the panel sits, so all of it
// is tested without BYOND.

export type Chip = { label: string; state: string; tone: string };

/** "KIND · ROLE · DISTANCE", whichever parts the server sent. */
export const inspectSubtitle = (
  kind?: string | null,
  role?: string | null,
  distance?: string | null,
): string =>
  [kind, role, distance]
    .filter((part): part is string => !!part)
    .map((part) => part.toUpperCase())
    .join(' · ');

/** The chip text: "R ARM: MISSING". */
export const chipText = (chip: Chip): string => `${chip.label}: ${chip.state}`;

/** The chip tones the stylesheet knows; anything else reads as plain info. */
export const chipTone = (tone: string): 'danger' | 'warning' | 'info' =>
  tone === 'danger' || tone === 'warning' ? tone : 'info';

/** The panel width in device pixels: its css width, capped by the map. */
export const panelWidth = (
  cssWidth: number,
  pixelRatio: number,
  mapW: number,
): number => Math.min(Math.ceil(cssWidth * pixelRatio), mapW);

/**
 * Top left of a panel w pixels wide in the top right corner of the map element, `margin` pixels in from the
 * edges and clamped inside it.
 */
export const placeTopRight = (
  w: number,
  mapW: number,
  margin: number,
): [number, number] => [Math.max(0, mapW - w - margin), Math.max(0, margin)];

/** The smallest the player can drag the panel to, in css pixels. */
export const MIN_PANEL_W = 300;
export const MIN_PANEL_H = 200;

/**
 * A size the player dragged the panel to, kept between the minimum and what fits in the map element (all css
 * pixels; `margin` is the gap kept to the map's edges).
 */
export const clampPanelSize = (
  w: number,
  h: number,
  mapCssW: number,
  mapCssH: number,
  margin: number,
): [number, number] => [
  Math.round(
    Math.max(
      MIN_PANEL_W,
      Math.min(w, Math.max(MIN_PANEL_W, mapCssW - margin * 2)),
    ),
  ),
  Math.round(
    Math.max(
      MIN_PANEL_H,
      Math.min(h, Math.max(MIN_PANEL_H, mapCssH - margin * 2)),
    ),
  ),
];
