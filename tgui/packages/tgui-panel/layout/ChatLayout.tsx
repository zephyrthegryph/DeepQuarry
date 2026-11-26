import { startMapSplitDrag } from './geometry';

/**
 * The column page's left edge: drags the map/column split live (BYOND's own
 * splitter only applies on release), then tells the server, which remembers
 * it (layout/mapsplit, map_split.dm).
 */
export function MapSplitHandle() {
  return (
    <div
      className="ChatSplitHandle ChatSplitHandle--left"
      onPointerDown={(event) =>
        startMapSplitDrag(event, (split) =>
          Byond.sendMessage('layout/mapsplit', { split }),
        )
      }
    />
  );
}
