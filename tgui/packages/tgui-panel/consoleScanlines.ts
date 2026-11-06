import { storage } from 'common/storage';
import { useEffect } from 'react';
import {
  SCANLINES_DISABLED_KEY,
  scanlineOverride,
} from 'tgui/layouts/consoleTheme';

const SCANLINE_VAR = '--console-scanline-strength';

/** Honours the lobby "Disable Scanlines" preference for the chat panel. */
export function useChatScanlines(): void {
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const value = scanlineOverride(await storage.get(SCANLINES_DISABLED_KEY));
      if (!cancelled && value !== null) {
        document.documentElement.style.setProperty(SCANLINE_VAR, value);
      }
    })();
    return () => {
      cancelled = true;
      document.documentElement.style.removeProperty(SCANLINE_VAR);
    };
  }, []);
}
