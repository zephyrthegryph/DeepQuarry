// The Inspect tab's logic (InspectTab.tsx): the subtitle, chips and portrait scale, so all of it is tested without
// BYOND. The server side is code/content/examine/inspect_panel.dm.

export type Chip = { label: string; state: string; tone: string };

export type Worn = { slot: string; name: string; ref: string };

export type InspectTabRef = { ref: string; name: string; active: boolean };

/** What the server sends for the Inspect tab (inspect_panel.dm payload()). */
export type InspectData = {
  target: string;
  kind?: string | null;
  role?: string | null;
  distance?: string | null;
  description?: string[];
  notes?: [string, string][];
  worn?: Worn[];
  body?: Chip[];
  tabs?: InspectTabRef[];
  portrait?: string | null;
  flavor?: string | null;
  show_flavor?: boolean;
  has_ooc?: boolean;
  primary?: { id: string; name: string } | null;
};

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

/** The largest the portrait is drawn, in css pixels, on either side. */
export const PORTRAIT_BUDGET = 160;

/**
 * The whole-number scale a w x h picture is drawn at: as large as fits the budget, never fractional, so pixels stay
 * square and the aspect ratio is kept. At least 1.
 */
export const portraitScale = (
  w: number,
  h: number,
  budget: number = PORTRAIT_BUDGET,
): number => {
  const side = Math.max(w, h);
  if (!(side > 0)) return 1;
  return Math.max(1, Math.floor(budget / side));
};
