import { CONSOLE_THEME, useConsoleScanlines } from 'tgui/layouts/consoleTheme';

/** Honours the lobby "Disable Scanlines" preference for the chat and stat panes (the console theme's own hook). */
export function useChatScanlines(): void {
  useConsoleScanlines(CONSOLE_THEME);
}
