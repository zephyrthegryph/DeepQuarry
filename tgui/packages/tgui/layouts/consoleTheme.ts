import { storage } from 'common/storage';
import { useEffect } from 'react';

/** The theme name windows pass to <Window theme=...>; styles/themes/console.scss. */
export const CONSOLE_THEME = 'console';

/** The lobby's "Disable Scanlines" preference; the console theme honours it. */
export const SCANLINES_DISABLED_KEY = 'lobby-filter-disabled';

const SCANLINE_VAR = '--console-scanline-strength';

/** The inline value that overrides the theme's scanline strength, or null to keep the theme's own. */
export const scanlineOverride = (disabled: unknown): string | null =>
  disabled ? '0' : null;

/** Applies the saved scanline preference to the document while a console-themed window is mounted. */
export function useConsoleScanlines(theme?: string): void {
  useEffect(() => {
    if (theme !== CONSOLE_THEME) {
      return;
    }
    let cancelled = false;
    (async () => {
      const disabled = await storage.get(SCANLINES_DISABLED_KEY);
      const value = scanlineOverride(disabled);
      if (cancelled || value === null) {
        return;
      }
      document.documentElement.style.setProperty(SCANLINE_VAR, value);
    })();
    return () => {
      cancelled = true;
      document.documentElement.style.removeProperty(SCANLINE_VAR);
    };
  }, [theme]);
}
