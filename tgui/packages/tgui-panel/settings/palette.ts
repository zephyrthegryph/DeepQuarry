/**
 * The native client's dark palette: the tgui-core theme values as hex, because
 * skin.dmf and winset take no CSS variables. interface/skin.dmf and
 * html/statbrowser.css cannot import this file, so palette.test.ts holds them
 * to these values.
 */
export const DARK_PALETTE = {
  /** tgui-panel --color-base, hsl(0, 0%, 12.5%) */
  base: '#202020',
  /** tgui-panel --color-section, hsl(0, 0%, 8.3%) */
  section: '#151515',
  /** --button-background-default, hsl(210, 37.5%, 45%) */
  primary: '#48739E',
  /** --button-background-selected, hsl(140, 70%, 40%) */
  selected: '#1FAD4E',
  /** --chat-text-color, hsl(210, 50%, 80%) */
  text: '#B3CCE6',
  /** --button-color */
  buttonText: '#FFFFFF',
  /** --color-hyperlink, hsl(220, 100%, 70%) */
  hyperlink: '#6699FF',
  /** --color-scrollbar-thumb on the base colour */
  scrollbarThumb: '#373737',
} as const;
