import { storage } from 'common/storage';
import { useEffect } from 'react';

/** The theme name windows pass to <Window theme=...>; styles/themes/console.scss. */
export const CONSOLE_THEME = 'console';

/** Every theme that has a stylesheet in styles/themes (consoleTheme.test.ts keeps this equal to the directory). */
export const WINDOW_THEMES: readonly string[] = [
  'abductor',
  'abstract',
  'admin',
  'algae',
  'bingle',
  'cardtable',
  'console',
  'crtsoul',
  'hackerman',
  'malfunction',
  'neutral',
  'ntos',
  'nuclear',
  'paper',
  'retro',
  'spookyconsole',
  'syndicate',
  'wizard',
];

/** The theme a window is drawn in: its own when it names one with a stylesheet, the console look otherwise (no name, '' or a name nothing styles). */
export function resolveTheme(theme?: string | null): string {
  return theme && WINDOW_THEMES.includes(theme) ? theme : CONSOLE_THEME;
}

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
