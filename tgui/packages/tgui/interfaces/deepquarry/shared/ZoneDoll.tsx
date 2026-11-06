// The zone-select doll: the same art and the same hit areas as the in-game HUD doll
// (icons/mob/screen/midnight.dmi "zone_sel" with the icons/mob/zone_sel.dmi overlays; the hit areas are
// GLOB.zone_sel_regions on the DM side, sent as data). Click a part to pick it.

import { useState } from 'react';
import { getIconFromRefMap } from 'tgui/events/handlers/assets';
import { Box } from 'tgui-core/components';

/** [zone, x1, y1, x2, y2] in pixels of the 32x32 art, counted from the bottom left; the first row containing the pixel wins. */
export type DollRegion = [string, number, number, number, number];

export const DOLL_SIZE = 32;
const BASE_ICON = 'icons/mob/screen/midnight.dmi';
const BASE_STATE = 'zone_sel';
const OVERLAY_ICON = 'icons/mob/zone_sel.dmi';

/** The zone under a pixel of the doll, or null. Same rule as zone_sel_zone_at() in screen_objects.dm. */
export function zoneAt(
  regions: DollRegion[],
  x: number,
  y: number,
): string | null {
  for (const [zone, x1, y1, x2, y2] of regions) {
    if (x >= x1 && x <= x2 && y >= y1 && y <= y2) {
      return zone;
    }
  }
  return null;
}

/** Pixel (1-based, from the bottom left) of a mouse position inside the doll's box. */
export function dollPixel(
  offsetX: number,
  offsetY: number,
  boxSize: number,
): [number, number] {
  const scale = boxSize / DOLL_SIZE;
  return [
    Math.floor(offsetX / scale) + 1,
    DOLL_SIZE - Math.floor(offsetY / scale),
  ];
}

type Props = {
  regions: DollRegion[];
  /** Zones currently chosen, highlighted on the doll. */
  selected: string[];
  /** Every zone that belongs with `zone` (both arms with one arm); defaults to the zone alone. */
  groupOf?: (zone: string) => string[];
  onPick: (zone: string) => void;
  /** Called with the zone under the pointer, null when it leaves the doll. */
  onHover?: (zone: string | null) => void;
  size?: number;
};

const layer = {
  position: 'absolute',
  top: 0,
  left: 0,
  width: '100%',
  height: '100%',
  imageRendering: 'pixelated',
  pointerEvents: 'none',
} as const;

export const ZoneDoll = ({
  regions,
  selected,
  groupOf = (zone) => [zone],
  onPick,
  onHover,
  size = 128,
}: Props) => {
  const [hover, setHover] = useState<string | null>(null);
  const baseRef = getIconFromRefMap(BASE_ICON);
  const overlayRef = getIconFromRefMap(OVERLAY_ICON);
  if (!baseRef || !overlayRef) {
    return null;
  }
  const hovered = hover ? groupOf(hover) : [];
  const setHovered = (zone: string | null) => {
    if (zone !== hover) {
      setHover(zone);
      onHover?.(zone);
    }
  };
  const zoneAtEvent = (event: React.MouseEvent<HTMLDivElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const [x, y] = dollPixel(
      event.clientX - rect.left,
      event.clientY - rect.top,
      rect.width,
    );
    return zoneAt(regions, x, y);
  };
  return (
    <Box
      position="relative"
      width={`${size}px`}
      height={`${size}px`}
      style={{ cursor: hover ? 'pointer' : 'default' }}
      onMouseMove={(event: React.MouseEvent<HTMLDivElement>) =>
        setHovered(zoneAtEvent(event))
      }
      onMouseLeave={() => setHovered(null)}
      onClick={(event: React.MouseEvent<HTMLDivElement>) => {
        const zone = zoneAtEvent(event);
        if (zone) {
          onPick(zone);
        }
      }}
    >
      <img alt="" src={`${baseRef}?state=${BASE_STATE}&dir=2`} style={layer} />
      {selected.map((zone) => (
        <img
          alt=""
          key={`on-${zone}`}
          src={`${overlayRef}?state=${zone}&dir=2`}
          style={layer}
        />
      ))}
      {hovered
        .filter((zone) => !selected.includes(zone))
        .map((zone) => (
          <img
            alt=""
            key={`hover-${zone}`}
            src={`${overlayRef}?state=${zone}&dir=2`}
            style={{ ...layer, opacity: 0.5 }}
          />
        ))}
    </Box>
  );
};
