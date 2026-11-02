/**
 * The Menu page: everything skin.dmf's native menu bar and link strip did. The
 * native bar stays in the skin and is hidden once this page mounts, so a panel
 * that fails to load still leaves it usable. menu.test.ts holds this list to the
 * skin's commands.
 */
export type MenuItem = { label: string; command: string };

export const GAME_ITEMS: MenuItem[] = [
  { label: 'Quick screenshot (F2)', command: '.screenshot auto' },
  { label: 'Save screenshot as... (Shift+F2)', command: '.screenshot' },
  { label: 'Reconnect', command: '.reconnect' },
  { label: 'Check ping', command: '.ping' },
  { label: 'Quit', command: '.quit' },
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
];

export const LINK_ITEMS: MenuItem[] = [
  { label: 'Wiki', command: 'wiki' },
  { label: 'Forum', command: 'forum' },
  { label: 'Rules', command: 'rules' },
  { label: 'Map', command: 'map' },
  { label: 'GitHub', command: 'github' },
  { label: 'Discord', command: 'discord' },
  { label: 'Patreon', command: 'patreon' },
];

/**
 * BYOND has no native borderless mode that keeps moving and resizing, so this is
 * a toggle: maximized with no title bar, and back. Maximize is cleared first
 * because the client ignores a title bar change on an already maximized window.
 */
export const FULLSCREEN_ON = { titlebar: false, 'can-resize': false };
export const FULLSCREEN_OFF = { titlebar: true, 'can-resize': true };

/** Every command the page can send, for the test. */
export function allCommands(): string[] {
  return [
    ...GAME_ITEMS.map((item) => item.command),
    ...ICON_SIZES.map((size) => iconSizeCommand(size.value)),
    ...ZOOM_MODES.map((mode) => zoomModeCommand(mode.value)),
    ...HELP_ITEMS.map((item) => item.command),
  ];
}
