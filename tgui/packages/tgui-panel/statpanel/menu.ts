/**
 * The Menu page: what skin.dmf's native menu bar did that nothing else does.
 * Reconnect and ping are in the chat box, quitting is the window's close
 * button, the chat is a window of the right-hand column, the chat log export is in
 * the chat settings (Export), and the web links are gone.
 */
export type MenuItem = { label: string; command: string };

export const GAME_ITEMS: MenuItem[] = [
  { label: 'Quick screenshot (F2)', command: '.screenshot auto' },
  { label: 'Save screenshot as... (Shift+F2)', command: '.screenshot' },
  { label: 'Fit viewport', command: 'fit-viewport' },
  { label: 'Active playtime', command: 'active-playtime' },
  { label: 'Server revision', command: 'show-server-revision' },
  { label: 'Changelog', command: 'changelog' },
];

/** Round commands that left the verb panel. */
export const ROUND_ITEMS: MenuItem[] = [
  { label: 'Who is online', command: 'who' },
  { label: 'Vote', command: 'vote' },
  { label: 'Round info', command: 'check-round-info' },
  { label: 'Observe', command: 'observe' },
  { label: 'Return to lobby', command: 'return-to-menu' },
  { label: 'Cancel camera view', command: 'cancel-camera-view' },
  { label: 'Incorporeal speed', command: 'set-incorporeal-speed' },
];

export const CHAT_ITEMS: MenuItem[] = [
];

const mapSet = (param: string, value: string | number) =>
  `.winset "mapwindow.map.${param}=${value}"`;

export const ICON_SIZES: { label: string; value: string }[] = [
  { label: 'Stretch to fit', value: '0' },
  { label: '128x128', value: '128' },
  { label: '96x96', value: '96' },
  { label: '64x64', value: '64' },
  { label: '48x48', value: '48' },
  { label: '32x32', value: '32' },
];

export const ZOOM_MODES: { label: string; value: string }[] = [
  { label: 'Nearest Neighbor', value: 'distort' },
  { label: 'Point Sampling', value: 'normal' },
  { label: 'Blur', value: 'blur' },
];

export const iconSizeCommand = (value: string) => mapSet('icon-size', value);
export const zoomModeCommand = (value: string) => mapSet('zoom-mode', value);
export const textModeCommand = (on: boolean) => mapSet('text-mode', `${on}`);

export const HELP_ITEMS: MenuItem[] = [
  { label: 'Admin help (F1)', command: 'request-help' },
  { label: 'Hotkeys', command: 'hotkeys-help' },
  { label: 'Character Setup', command: 'character-setup' },
  { label: 'Game Options', command: 'game-options' },
  { label: 'Character Directory', command: 'character-directory' },
  { label: 'Request Automated Advice', command: 'request-automated-advice' },
];

/** The Menu page's sections the panel search reaches (the display controls are not commands one types). */
export const MENU_SECTIONS: { name: string; items: MenuItem[] }[] = [
  { name: 'Game', items: GAME_ITEMS },
  { name: 'Round', items: ROUND_ITEMS },
  { name: 'Chat', items: CHAT_ITEMS },
  { name: 'Help', items: HELP_ITEMS },
];

/** The Status view's quick row: what a player reaches for most. */
export const QUICK_ITEMS: MenuItem[] = HELP_ITEMS.slice(0, 4);

/** Runs a client command after our own focus handling. */
export function run(command: string) {
  setTimeout(() => Byond.command(command), 0);
}

/** Every command the page can send, for the test. */
export function allCommands(): string[] {
  return [
    ...GAME_ITEMS.map((item) => item.command),
    ...ROUND_ITEMS.map((item) => item.command),
    ...ICON_SIZES.map((size) => iconSizeCommand(size.value)),
    ...ZOOM_MODES.map((mode) => zoomModeCommand(mode.value)),
    ...HELP_ITEMS.map((item) => item.command),
  ];
}
