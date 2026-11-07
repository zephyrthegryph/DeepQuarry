/**
 * The DQ UI layer: the few components every DQ surface shares, built on
 * tgui-core (never a replacement for it). Imported by tgui windows, the chat
 * and stat panel (tgui-panel). Tokens and
 * effects: tgui/styles/console.scss; styles: tgui/styles/dq/. Rules:
 * doc/rewrite/proposals/ui_library.md.
 */

export { ListRow, ListRows } from './ListRow';
export { moveBefore } from './reorder';
export { type Tab, Tabs, type TabsLayout } from './Tabs';
export { CloseButton, TitleBar } from './TitleBar';
export {
  FormattedBackdrop,
  FormattedText,
  LanguagePreview,
} from './speech/LanguagePreview';
export {
  buildPreview,
  type LanguageRules,
  type Preview,
} from './speech/parseLanguages';
export {
  activeAt,
  SHORTCUT_MARKERS,
  type TextEdit,
  toggleLanguage,
  toggleMarker,
} from './speech/shortcuts';
