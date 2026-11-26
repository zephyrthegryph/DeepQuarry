/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

/** Skin windows, splitters and browsers. The client is dark only: skin.dmf sets it, palette.test.ts holds it. */
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
