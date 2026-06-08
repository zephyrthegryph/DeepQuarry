import { useMemo } from 'react';
import type { Overlay, PlushieConfig } from './types';

export function downloadJson(filename: string, data: PlushieConfig) {
  const blob = new Blob([JSON.stringify(data)], {
    type: 'application/json',
  });
  Byond.saveBlob(blob, filename, '.json');
}

/**
 * Parses an imported JSON file and sends the config to the backend via act.
 * `act` must be provided by the calling component (obtained from useBackend).
 * This is a plain function — it does not call any React hooks.
 */
export function handleImportData(
  importString: string | string[],
  act: (action: string, params?: Record<string, unknown>) => void,
): void {
  const ourInput = Array.isArray(importString) ? importString[0] : importString;
  try {
    const parsedData: PlushieConfig = JSON.parse(ourInput);
    act('import_config', { config: parsedData });
  } catch (err) {
    console.error('Failed to parse JSON:', err);
  }
}

export function useOverlayMap(overlays: Overlay[]) {
  return useMemo(
    () => Object.fromEntries(overlays.map((o) => [o.icon_state, o])),
    [overlays],
  );
}
