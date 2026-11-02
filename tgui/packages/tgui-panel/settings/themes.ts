/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { DARK_PALETTE } from './palette';

let setClientThemeTimer: NodeJS.Timeout;

/** Skin windows, splitters and browsers. Dark is their default in skin.dmf. */
export const SKIN_PANES = [
  'mainwindow',
  'mainvsplit',
  'rpane',
  'rpanewindow',
  'outputwindow',
  'legacy_output_selector',
  'output_legacy',
  'output_browser',
  'browseroutput',
  'statwindow',
  'statbrowser',
] as const;

/** The top link buttons. Patreon keeps its own green. */
export const SKIN_BUTTONS = [
  'discord',
  'github',
  'mapb',
  'rulesb',
  'forumb',
  'wikib',
] as const;

/**
 * The winset for a client theme. BYOND has no skin stylesheet, so a theme is
 * set per element; palette.test.ts fails on a name that left skin.dmf. Native
 * title and menu bars take no colour from winset, they follow Windows.
 */
export function clientThemeWinset(name: string): Record<string, string> {
  const isDark = name === 'dark' || name === 'vchatdark';
  const params: Record<string, string> = {};
  for (const pane of SKIN_PANES) {
    params[`${pane}.background-color`] = isDark ? DARK_PALETTE.base : 'none';
    params[`${pane}.text-color`] = isDark ? DARK_PALETTE.text : '#000000';
  }
  for (const button of SKIN_BUTTONS) {
    params[`${button}.background-color`] = isDark
      ? DARK_PALETTE.primary
      : 'none';
    params[`${button}.text-color`] = isDark
      ? DARK_PALETTE.buttonText
      : '#000000';
  }
  params['output.background-color'] = isDark ? DARK_PALETTE.section : 'none';
  params['output.text-color'] = isDark ? DARK_PALETTE.text : '#000000';
  return params;
}

/** Applies a client theme to the skin and the stat panel. */
export function setClientTheme(name) {
  // Transmit once for fast updates and again in a little while in case we won
  // the race against statbrowser init.
  clearInterval(setClientThemeTimer);
  Byond.command(`.output statbrowser:set_theme ${name}`);
  setClientThemeTimer = setTimeout(() => {
    Byond.command(`.output statbrowser:set_theme ${name}`);
  }, 1500);

  Byond.winset(clientThemeWinset(name));
}
